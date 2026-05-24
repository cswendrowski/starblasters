# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

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
- [x] **Hyper Mode** — `073a709`. 3 s supercharged primary + invuln.
- [x] **Phase Shift** — `073a709`. 2 s invuln + bullet cancel.
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
- [ ] **WaveGeneratorV2 + scene removal** — V2 wave path is now unreachable from the dev menu but the script + scene + dev/wave_tester.tscn remain on disk. Safe to delete once nothing in the runtime path references it (main.gd's `wave_v2_knobs` meta branch is dead code).
- [ ] **Old Ship Sizer scene + script** — left on disk after the Shipyard merge; unreachable from the dev menu. Same cleanup posture as V2 wave.
- [ ] **Drone autonomy** — current Drone Bits + Drone Swarm drones only fire when the player fires primary (piggyback model). Truly independent target acquisition + cadence is a follow-up if the feel warrants. [PARTIAL: 2026-05-21 — Drone Swarm now autonomous, picks bosses then nearest enemy, fires basic blaster (commit `e6c42a6`). Drone Bits was redesigned into Shield Drones (ablative, non-firing) in the same commit.]

## Cobalt 2026-05-21 backlog

- [ ] **Dynamic animated nebula** — adjust nebula to be dynamic, animated, noise-based, and seamless. Current V3 nebula uses `nebula2.gdshader` (domain-warped + filaments, scroll_offset driven from layer accumulated scroll). May need new shaders for a fully animated swirl. Build prototype + capture for review.
- [ ] **V3 parallax color correction + adjustment sliders not working** — Brightness / Contrast / Colorization in the tuner aren't tinting V3 layers reliably. After the CanvasGroup removal we're on per-child modulate via the tuner's fallback path; need to confirm whether modulate IS being written and whether Parallax2D propagates it through tiled draws in Godot 4.3. **Also add a blend-mode dropdown** for the per-layer color system (Mix / Add / Multiply / Screen).
- [ ] **Phase Shift + Focus supers not working** — investigate why both super actions are no-op when triggered. Verify the super_part hook + activate() path.
- [ ] **Drone Swarm super emit point** — drones should emit from the player center on activation (currently spawn at the wing-halfspan offset).
- [ ] **Direction-based player sprite rotation** — the player ship sprite used to rotate based on horizontal input direction; this seems to have been lost in the horizontal-rework branch. Restore the frame-swap / rotation behaviour.

## Enemy rework backlog 2026-05-24

- [ ] **480-speed Dart reaction-test variant** ("Sprint Dart") — distinct enemy for late-game; reuses Dart sprite + faster movement (~480 px/s), no shoot. Spun off from the 2026-05-24 speed pass where Dart was dropped from 480 → 360 for fair-play; the 480 tier still wants to exist as a deliberate reaction test.
- [ ] **Per-enemy-class loiter timing** — Beam Shooter / Gunship / Crystal / Cruiser / Drone Carrier currently share the identical `enter 110 / hold 3 / exit accel 300 max 350` cadence on the `Loiter` pattern. Fold into a per-enemy-class rework like chaff got (medium tier ~130 / 3 / 400-450; large tier ~90 / 4 / 280 per the §3 doc). Out of scope of the 2026-05-24 speed pass.
- [ ] **Bullet library refactor (B2)** — replace the single `enemy_bullet.tscn` + 200 px/s baseline with a roster of bullet variants (dumb 220 / aimed 300 / heavy 180 / fast 240) selectable per shoot_pattern. Doc audit §3 + §1 reference bands. Cheapest path is a `bullet_speed` @export on `shoot_pattern.gd` honored in `_spawn_bullet`, but designer prefers a real bullet-resource roster rather than a single override knob.
- [ ] **Bulwark drift retune** — bulwark_drift currently 25/36/0.35; doc §3 proposes 50/50/0.45. Folded into a separate Bulwark-turret pass alongside the shielding rework.

## Already-done (since this list was captured)

- Wave editor with full CRUD + playtest + state persistence.
- Movement Pattern Editor + Shoot Pattern Editor (reflection-driven, live preview).
- Weapon Editor (Mk slider, DPS readout, tracer preview).
- HD viewport pattern (`Window.content_scale_size` swap) for text-dense dev pages.
- Wave Editor → pattern editor round-trip via `pattern_editor_return_scene` meta.
