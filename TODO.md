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
- [ ] **Drone autonomy** — current Drone Bits + Drone Swarm drones only fire when the player fires primary (piggyback model). Truly independent target acquisition + cadence is a follow-up if the feel warrants.

## Already-done (since this list was captured)

- Wave editor with full CRUD + playtest + state persistence.
- Movement Pattern Editor + Shoot Pattern Editor (reflection-driven, live preview).
- Weapon Editor (Mk slider, DPS readout, tracer preview).
- HD viewport pattern (`Window.content_scale_size` swap) for text-dense dev pages.
- Wave Editor → pattern editor round-trip via `pattern_editor_return_scene` meta.
