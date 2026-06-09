# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

## M6c polish backlog (scoped 2026-06-07)

Remaining from Roman's batch after the engine-trail / reorg / weapon-fix / shader passes
landed. Grouped by effort.

**Bespoke per-enemy fixes (small, need eyeball):**
- [ ] **s_s_rush movement-based facing** — auto_rotate is on by default but Roman reports
  it's not facing its travel. Eyeball: not turning at all / faces down / spins? Likely an
  auto_rotate seed or the Engine-marker-under-CollisionShape transform. (`enemy_s_s_rush.tscn`)
- [x] **z_s_sword firing** — DONE (combat session, `35712ff` "sword rolling broadside firing").
- [x] **retro/hold turn-during-jiggle** — DONE (combat session, `cdf4b3a` "loiter holders don't turn
  the wrong way during the jiggle").

**Wave/pattern work (larger, director + wave-gen):**
- [ ] **Cohesive chaff waves** — bomb-drone/dart waves are too long + sparse. Want
  multi-layered walls, tightly-spaced walls with navigable lane gaps, L→R (and R→L) sweeps,
  and inward→out / outward→in patterns. (`scripts/levels/director.gd` + `wave_generator.gd`)
- [ ] **Speed audit to the 1–8 px/f rungs** — `fast_straight` done (→300); audit every other
  movement key + sector scaling so nothing common sits past 6 px/f. >6 px/f = reflex tier:
  rare, mid/late only. (`enemy_roster.make_movement` + `enemy_core` sector scale + `clarity.gd`)
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
- [ ] **Tracer art hframes/masking** — tracer sprites render doubled with an offset glow;
  check hframes + frame masking on the tracer textures (`enemy_tracer` / `tracer-*` + variants).

### Patterns (director / wave-gen)
- [ ] **Minefield hazard = real wave numerics + dense navigable patterns.** Same enemy counts
  as a normal wave; dense waves with patterns demanding careful navigation / focus-threading /
  shoot-through. (`scripts/levels/levels_v2.gd` minefield + director)
- [x] **p_s_green waves over-rely on curves** — DONE (combat session, `ab1b7e2` "p_s_green wave variety (drift + straight variants, less weave)").
- [ ] **Conductor must not repeat patterns** — if reused, reverse them on alternating waves or
  mix with lane patterning (L→R, R→L, in/out sweeps). (`director.gd` conductor choreography)
- [ ] **Bomb-drone waves too thin again** — come as walls with dodge gaps the player must enter,
  not 1–2 stragglers. (shared with round-1 "cohesive chaff waves")
- [ ] **Mix-and-match lane patterns** — different lanes running different patterns in one wave
  for visual texture.
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

### Recycling
- [ ] **Recycling breaks composed formations.** Recycled units re-enter as noise, devolving
  pincer/wall patterns. The conductor must handle recycling: route recycled enemies into the
  NEXT wave pool / a fresh intervening pattern / fold them into the ongoing wave, so composed
  patterns stay intact. (`director.gd` + `enemy_core` recycle hook)
- [ ] **Unified pseudo-mid recycle layer.** Commit to a single core recycling layer modeled on
  the missile_cruiser's pseudo-parallax layer (same shading + placement), so ALL recycling
  enemies look consistent. (factor missile_cruiser's pseudo-parallax into a shared mechanism)

### Background (likely separate scope)
- [x] **Per-row planets are static** — DONE (lead 2026-06-08, `c36a044`). Live backdrop is the V4
  coordinator (`scripts/parallax/backdrop_coordinator.gd`), NOT `galaxy_backdrop.gd`. Folded
  `current_node_id` into the coordinator RNG so each node's decorative composition varies, and mixed
  `run_seed` into every per-POI planet/deco seed in `sector_map_v3.gd` (in lockstep so map↔combat
  planet parity holds). Per-row variety now keys off run + node identity. NEEDS EYEBALL across runs.

### Sector Map (likely separate scope)
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
- [x] **Intensity ramp** — DONE (lead 2026-06-08, `c36a044`). Levels with ≥5 waves lift to the Main
  theme on the final 2 waves (the `wave_started → set_combat_progress` pipe already existed in
  `main.gd`, no director edit needed). NEEDS EYEBALL.
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

## Follow-ups (not in scope this pass)

- [ ] **Shipyard stat editor / sprite picker** — full unit authoring tool (edit HP, bounty, speed, hitbox, sprite per enemy in-game). Deferred — bigger UI refactor than this pass. Godot inspector on enemy `.tscn` is the authoritative path until then.
- [ ] **Gamepad rebind in-app** — keyboard rebind UI persists across sessions, but gamepad button reassignment still requires editing `project.godot`.
- [x] **WaveGeneratorV2 + scene removal** — DONE (files already deleted: `wave_generator_v2.gd` +
  `dev/wave_tester.gd`/`.tscn` gone; no `wave_v2_knobs` references remain in code).
- [x] **Old Ship Sizer scene + script** — DONE (`dev/ship_sizer.gd`/`.tscn` gone).
- [ ] **Drone autonomy** — current Drone Bits + Drone Swarm drones only fire when the player fires primary (piggyback model). Truly independent target acquisition + cadence is a follow-up if the feel warrants. [PARTIAL: 2026-05-21 — Drone Swarm now autonomous, picks bosses then nearest enemy, fires basic blaster (commit `e6c42a6`). Drone Bits was redesigned into Shield Drones (ablative, non-firing) in the same commit.]

## Cobalt 2026-05-21 backlog

- [ ] **Dynamic animated nebula** — adjust nebula to be dynamic, animated, noise-based, and seamless. Current V3 nebula uses `nebula2.gdshader` (domain-warped + filaments, scroll_offset driven from layer accumulated scroll). May need new shaders for a fully animated swirl. Build prototype + capture for review.
- [ ] **V3 parallax color correction + adjustment sliders not working** — Brightness / Contrast / Colorization in the tuner aren't tinting V3 layers reliably. After the CanvasGroup removal we're on per-child modulate via the tuner's fallback path; need to confirm whether modulate IS being written and whether Parallax2D propagates it through tiled draws in Godot 4.3. **Also add a blend-mode dropdown** for the per-layer color system (Mix / Add / Multiply / Screen).
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
- [ ] **Per-enemy-class loiter timing** — Beam Shooter / Gunship / Crystal / Cruiser / Drone Carrier currently share the identical `enter 110 / hold 3 / exit accel 300 max 350` cadence on the `Loiter` pattern. Fold into a per-enemy-class rework like chaff got (medium tier ~130 / 3 / 400-450; large tier ~90 / 4 / 280 per the §3 doc). Out of scope of the 2026-05-24 speed pass.
- [ ] **Bullet library refactor (B2)** — replace the single `enemy_bullet.tscn` + 200 px/s baseline with a roster of bullet variants (dumb 220 / aimed 300 / heavy 180 / fast 240) selectable per shoot_pattern. Doc audit §3 + §1 reference bands. Cheapest path is a `bullet_speed` @export on `shoot_pattern.gd` honored in `_spawn_bullet`, but designer prefers a real bullet-resource roster rather than a single override knob.
- [ ] **Bulwark drift retune** — bulwark_drift currently 25/36/0.35; doc §3 proposes 50/50/0.45. Folded into a separate Bulwark-turret pass alongside the shielding rework.

## Hazard rework backlog 2026-05-24

- [ ] **Overhaul Asteroid Hazard** — current asteroid_field level needs a structural pass. Cody flagged background asteroids overlapping the playspace; APT confirmed the underlying behavior isn't what was described and the level wants a broader rework, not a spawn-range patch. Defer until the hazard rework slot opens.

## New 2026-05-25 (designer)

- [x] **Cull the sector V3 dev menu** — done in dev tooling cleanup (this commit). Also dropped WaveGeneratorV2 + dev/wave_tester + the old dev/ship_sizer in the same pass. Grid annotation pattern preserved in `scripts/dev/grid_overlay.gd` for the new UI Plotter.
- [x] **POI visited state — disable lights + decor on resolve** — `641cb79`. Completed POIs skip planet/asteroid/cluster decoration + pulse-glow / glitter / hover label.
- [x] **Grid-based screen designer** — shipped as `scripts/dev/ui_plotter.gd` + `scenes/dev/ui_plotter.tscn`. Pick a player screen from the modal, overlay 8/16/32px annotated grid (G/L hotkeys), live mouse-cell readout. Reuses the V3 sector map grid via `scripts/dev/grid_overlay.gd`.

## Outstanding 2026-05-25 (sweep)

Captured from research docs (`docs/*.md`), recent commit bodies, agent "Open" flags, and project memory. Existing entries above not duplicated.

### Bosses (`docs/boss_proposals_2026-05-24.md`)

- [x] **Boss roster gaps — Spinwright + Conductor — DONE (verified 2026-06-07).** The 7-boss roster is COMPLETE and live: `boss.gd` (Commander), `boss_reaver` (Lash), `boss_sentinel`/`boss_aegis` (Aegis), `boss_howler`, `boss_voidmaw`, `boss_spinwright`, `boss_conductor` — all with `scenes/enemies/boss_*.tscn` + wired into `wave_generator._pick_boss`, `run_state._pick_row_bosses`, and the dev menu. (Source: `docs/boss_proposals_2026-05-24.md` §4)
- [x] **Tethered-orbit movement — DONE (verified 2026-06-07).** The Conductor's two satellites mirror player X + orbit via `scripts/enemies/conductor_satellite.gd` (bespoke satellite script, not a `patterns/` movement resource — same end behavior). (Source: `docs/boss_proposals_2026-05-24.md` §4 Conductor)
- [ ] **Biome reskins per boss** — palette + one attack tweak variants to double visual variety once base roster ships. (Source: `docs/boss_proposals_2026-05-24.md` §5)
- [ ] **Shared boss-enrage VFX helper** — phase-transition flash + screen-shake helper so HP-gate transitions read consistently across bosses. (Source: `docs/boss_proposals_2026-05-24.md` §6 open question 6)
- [ ] **Boss `conflict_tags` "never-pair" enforcement** — Voidmaw shouldn't pair with Commander; Howler shouldn't pair with Reaver/Lash; etc. (Source: `docs/boss_proposals_2026-05-24.md` §6 open question 4)
- [ ] **Bosses with omni-strafe** — designer-flagged variation idea, currently deferred. (Source: task list #12)

### Enemies / Bullets

- [ ] **Bullet library refactor (B2)** — `BulletVariant` Resource + 7 variants (Basic/Aimed Sniper/Heavy Slug/Spread Pellet/Plasma Orb/Tracker/Burst Round); APT sprite list ready. Currently every enemy bullet is one scene at 200 px/s. (Source: `docs/bullet_library_2026-05-24.md`; task #17 deferred. Already in Enemy rework backlog above — keeping single citation.)
- [ ] **Boss bullet primitives accept `bullet_variant`** — `boss_base.fire_aimed_burst` / `fire_ring` default to Basic; add optional variant param. (Source: `docs/bullet_library_2026-05-24.md` §6 open question 4)
- [ ] **Wave-gen `bullet_variant_override` knob** — themed waves force all enemies to fire variant X. Add if themed waves land. (Source: `docs/bullet_library_2026-05-24.md` §6 open question 2)
- [ ] **Per-pattern `bullet_speed` override** — `@export var bullet_speed: float = -1.0` on `shoot_pattern.gd` honored in `_spawn_bullet`. Cheapest path before the full bullet-library refactor; aimed shots want 300 not 200. (Source: `docs/enemy_speeds_2026-05-24.md` §3, §5)
- [ ] **Chaff-speed sector scaling** — `+5%/sector` cap `+25%` if player damage already scales. (Source: `docs/enemy_speeds_2026-05-24.md` §5 open question 4)
- [ ] **`AimedShot.lead_factor` on Skirmisher** — flip from 0 to ~0.15 for "experienced gunner" feel without raising bullet speed. (Source: `docs/enemy_speeds_2026-05-24.md` §4)
- [ ] **Hunter Drone kamikaze bounty cancel** — `enemy_roster.gd:97` lists 5 bounty; `enemy_hunter_drone.gd` says "no bounty for kamikaze hit" — verify the cancel-on-hit path actually fires. (Source: `docs/economy_2026-05-24.md` §5)

### Economy (`docs/economy_2026-05-24.md`)

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
- [x] **`wanted` / `dangerous` POI bounty multipliers** — CLOSED (Roman call sheet #6: "no bonus
  bounty"). `wanted` already gives +20% via the director; `dangerous` stays damage-only. Instead, the
  active sector modifiers are now SHOWN to the player in the outpost (#6, `daa8594`).
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
- [ ] **Manage Ship modal PartTier badges + 20% sell UI** — modal not yet using the shared `part_tier.gd` helper or the 20% resale. (Source: commit `cd71f44` open flag)
- [x] **Outpost density hard clamp → probabilistic** — SUPERSEDED by the outpost-hub redesign (#4):
  outposts are a sector-map button now, not POIs, so there's no per-sector outpost count to tune.

### Visual / VFX

- [ ] **Dynamic animated nebula** — already in Cobalt 2026-05-21 backlog above; keep.
- [ ] **V3 parallax color sliders not working + blend-mode dropdown** — already in Cobalt 2026-05-21 backlog above; keep.
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

### Weapons / Architecture (`docs/weapon_architecture_2026-05-24.md`)

- [ ] **`scripts/bullet.gd` + `scripts/bullet_wave.gd` live at `scripts/` root** — siblings are in `scripts/projectiles/`. Move + update `.tscn` paths. (Source: `docs/weapon_architecture_2026-05-24.md` §5)
- [x] **`drone_bits.apply()` doesn't snapshot prior `ship.drone_bits` array** — DONE (lead 2026-06-08, `85bf63c`). apply() snapshots, unapply() restores. (Impact nil today; contract now symmetric.)
- [ ] **Heavy Blaster cooldown lerp 0.20 → 0.18 per Mk** — tiny per-Mk drift introduced by refactor; can be reverted by setting constant `0.20`. (Source: commit `2083c59` open flag)
- [x] **basic_blaster + spread_cannon snapshot/restore asymmetry** — STALE (verified lead 2026-06-08). The `weapon_part` base already snapshots + restores `weapon_style`/`fire_sfx_kind` via `_all_snapshot_keys()`; no asymmetry in current code. Closing.
- [ ] **`drone_bits.tres` + `drone_swarm.tres` stale defaults** — open in editor, re-save against current `.gd` defaults so Weapon Editor doesn't surface stale values. (Source: `docs/redundancy_audit_2026-05-21.md` §Weapons action items)
- [ ] **Weapon mounts: per-Part `fire_offset: Vector2`** — so wing-mounted vs nose-mounted weapons don't all spawn at `(0,-10)`. (Source: `docs/weapon_architecture_2026-05-24.md` §4 item 5)
- [ ] **`burst_shot.tres` — author designer instance** — `scripts/enemies/shoot_patterns/burst_shot.gd` has no `.tres` companion. (Source: `docs/redundancy_audit_2026-05-21.md` §Enemy shoot patterns)

### Dev tools

- [x] **WaveGeneratorV2 + Ship Sizer removal** — DONE (files gone; see Follow-ups above).
- [ ] **`scenes/sector_map.tscn` orphan** — pre-existing V1 map, referenced by `feature_showcase.gd` + `tools/parse_check.ps1`. Roman: "leave it for now, flag for cleanup later." (Source: memory `project_sector_map_v3.md` §Known open issue 3)
- [ ] **`SmokeTrail.new(palette)` factory** — consolidate `damage_smoke_trail.gd` + `missile_smoke_trail.gd` (~90% shared code) once a third smoke emitter appears. Not urgent. (Source: `docs/redundancy_audit_2026-05-21.md` §Particle effects)

## End-of-run summary + run history + run timer (rolled in 2026-06-08)

Full scoping in `docs/run_summary_scope_2026-06-01.md` (re-audited 2026-06-05). Status: **scoped,
not built — no stats instrumentation has landed.** Splits into a cheap core + an expensive tail.
NOTE: most hooks live in `player.gd` / `enemy_base.gd` / `main.gd` — shared / combat-arena files;
coordinate with the combat session before instrumenting those hot paths.

- [ ] **Phase 1 — `RunStats` core (~½–1 day, ship first).** Add a run-wide stats accumulator on the
  `Run` autoload; reset it in `new_run()` alongside the other run-scoped fields. Surface Tier-1 stats
  that already have signals: **damage taken** (shield vs hull, off `Player.damaged` 0/1), **bounty
  gained** (off `Run.record_kill()`), **asteroids destroyed** (roll up `_asteroids_killed_this_level`
  instead of resetting). Redo the death summary (`run_summary.gd`) to show them. Reuses
  `cleared_summary.gd`'s per-enemy-type tally + sprite previews. Proves the `RunStats` pattern before
  touching hot paths.
- [ ] **Run Timer (fold into Phase 1 — near-zero marginal).** `run_time_seconds` on `Run`, **active
  combat time only** (recommended): a pausable delta-accumulator keyed on `playing` auto-excludes
  intro/outro/pause/map/shop/transitions. Zero in `new_run()`, accumulate in `_on_level_cleared`,
  flush in `_on_player_died`. Persist via `RunSave` (`_SAVE_FIELDS` + a `@export` mirror — both sides
  or it's silently dropped). Optional per-level breakdown into `RunStats`. **Open call:** also show
  wall-clock total (B), or active-only (A)? Stop-on-victory point doesn't exist yet (see Phase 3).
- [ ] **Phase 2 — new instrumentation (~1–1.5 days).** Tier-2/3 hooks with no signal today:
  **shots fired** (hook `player.gd` fire fns — hot path, no per-shot alloc), **shots hit / accuracy**
  (hook `enemy_base.gd take_hit`; counting model LOCKED = per-projectile-spawned, multi-hit can
  exceed 100%), **bounty spent** (single choke-point over the outpost's bare `run.bounty -=`),
  **mines cleared** (via kill path / scene_path), **locations/stations/signals visited** (via reliable
  `mark_node_completed` + node-type counting — the V3 map bypasses `mark_node_visited`), **unique
  weapons used** (net-new hook on active-cannon change/fire).
- [ ] **Phase 3 — victory / "patrol complete" path (~½ day).** NET-NEW code path: `run_summary.tscn`
  is reached only on death today; final-sector clear funnels through the endless-mode prompt. Need a
  real patrol-complete flow + screen, and `RunStats` must snapshot into history at BOTH exit points
  (death AND victory) before reset. This is also where the run timer's stop-on-victory wires in.
- [x] **Phase 4 — dated run-history index** — DONE (lead 2026-06-08, `1c86ba2`). `user://run_history.json`
  (capped to last 50) written on the death flow from stats Run already tracks; "Run History" main-menu
  button → `scenes/run_history.tscn` list. Victory hook will call the same `record_run_history()` once
  a patrol-complete path exists (Phase 3).

## Supers / Modes / Modules taxonomy refactor (rolled in 2026-06-08)

**STANCE part = BUILT** (`docs/shift_mode_system_2026-06-08.md`, `0ef66ad`..`9b55e47` + `9845725`).
One permanent Super (Smart Bomb, X) + a one-of-three stance slot (Focus default / Phase / Hyper) on
Shift, with per-mode resources, HUD meter, outpost purchase + signal-event finds. The old
`docs/supers_modes_modules_2026-06-05.md` (Mode-Energy gauge / ace-chain) is SUPERSEDED.

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

REMAINING — the **passive-module layer** (separate from stances; NOT built):
- [ ] **Reify defensive systems as Modules.** Move Shield / Hull Regen / Hull
  Plating from abstract `Run` int Mk-keys into passive Part Resources (or cheaper: keep as `Run` ints
  but PRESENT them in the bay). Shield becomes a default-equipped passive (dropping it = deliberate
  glass-cannon). OPEN DECISION: reify vs present; 4 vs 3 passive slots.
- [ ] **Passive-module roster (~10 picks for ~3 free slots).** Shield Core (default), Repair Nanites,
  Ablative Plating (deterministic every-Nth, not RNG), Intercept Drones, Splinter Rounds, Targeting
  Computer (crit), Overclock Core (fire ramp), Overcharge Core (+dmg/−shield), Adrenal Surge
  (low-hull scaling), Tractor Coil (pickup magnet), Siphon Core (kills → shield charge, **never Mode
  Energy**). Each adds a *mechanic*, Mk.1–9 scalable. Full roster + cut list + build archetypes in
  spec §15.

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
