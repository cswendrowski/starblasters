# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

## Controls + Player

- [x] **Rebind to genre conventions** — `5d36dcc`. Z+Space = primary, C = secondary, X = super, Shift = focus, Q/E weapon swap.
- [x] **Focus Mode** — `5d36dcc`. Hold Shift → speed × 0.55 + hitbox dot at player center.
- [x] **Settings remap UI** — `1cf36be`. Options overlay Controls section, click-to-rebind per action. Keyboard only (gamepad rebind in-app deferred). Session-only persistence — cross-session rebind serialisation is a polish follow-up.
- [x] **Autofire toggle** — `fba545a`. Settings.autofire (checkbox in Options).
- [x] **Gamepad support** — `94be6ab`. D-pad / left stick for movement; A/B/X/Y + LB for action buttons. Standard shmup layout.

## Weapons + Parts

- [x] **Secondary fire pipeline + shuffle missile/rocket to HARDPOINT_WING** — `278066e`. player.gd grew secondary_bullet_scene / secondary_cooldown / secondary_damage / secondary_homing + _secondary_t. Seeking Missile + Rocket Pod's apply() now writes there, slot_type = HARDPOINT_WING.
- [x] **Spread Cannon** — `83cd9f5`. Fans bullets across an arc, Mk scaling adds bullets.
- [x] **Smart Bomb** — `b9e3458`, `ee904d9`. Screen-clear + heavy damage + 0.6s invuln. Auto-equipped Mk.1 on starting loadout.
- [x] **Hyper Mode** — `073a709`. 3 s supercharged primary (bypass GunCooldown + 2× damage) + invuln.
- [x] **Phase Shift** — `073a709`. 2 s invuln + bullet cancel.
- [ ] **Drone Swarm** (super) — deferred; needs autonomous drone enemy scenes that don't exist yet.
- [ ] **Side Pods / Drone Bits** — secondary supplements in HARDPOINT slots, expand the secondary roster.
- [x] **Outpost refill for super charges** — `3cbfef0`. Free refill on outpost visit (paid in-station button is a follow-up polish).
- [x] **HUD super_charges pip strip** — `e41cf49`. Gold = remaining, dim = spent. Rebuilds on Mk change.
- [x] **Filter Weapon Editor list by slot_type** — `ff47632`. SlotFilter dropdown with All / Primary / Secondary / Super.
- [x] **Touhou death-bomb hook** — `e41cf49`, `ee904d9`. On fatal hit, auto-fire super (consumes a charge, grants invuln) instead of dying.
- [x] **Hook PartFactory to load weapons from resources/weapons/.tres** — `c54befc`. Both starting loadout AND shop pool consult .tres first, fall back to script defaults. Weapon Editor saves now affect in-game balance.

## Onboarding

- [x] **Update onboarding to teach new keybinds + Mk system** — `57faad3`. Controls page now lists Z/C/X/Shift. New Parts & Marks page explains Mk.1–9 scaling.

## Dev Menu Cleanup

- [x] **Remove obsolete buttons** — `35a66a2`. Test Bed, Movement Test, UI Designer, Wave Tester gone. `WaveGeneratorV2` still on disk; pull when nothing references it.
- [ ] **Merge Ship Sizer + Shipyard → unified Shipyard.** Edit any ship / enemy: stats (HP, bounty, speed, hitbox), sprite, scale, orientation flip. Should be the one tool for unit authoring. **Deferred — bigger UI refactor than fit this session.**
- [x] **Unified Test Combat launcher** — `eb45a8f`. One modal fans out to Test Level / Hazard / Boss Fight.

## Asteroid Lab

- [x] **Fix slider wiring** — `7835360`. Size slider now drives the inner ColorRect (was a no-op). Pivot centered for spin. Investigation notes preserved below for reference.
- [ ] **Fix slider wiring (resolved).** Investigation notes:
  - `_on_slider_changed` IS connected to all 6 sliders and calls `_regenerate()`.
  - Asteroid is `res://Planets/Asteroids/Asteroid.tscn` — a Planet root (script holder) with one child `Asteroid` ColorRect that owns the shader material.
  - `set_seed(sd)` and `set_pixels(amount)` mutate the inner ColorRect's shader. Should work — the material is per-instance-duplicated in `_regenerate`.
  - **Likely problem with Size slider**: only resizes the outer Planet Control. The inner ColorRect uses absolute offsets (`offset_right=100, offset_bottom=100`) and gets its size from `set_pixels` separately. Size slider should probably drive `pixels` OR resize the inner ColorRect.
  - **Likely problem with Spin**: meta set on outer Planet root, `_process` reads it and rotates `_visual.rotation`. May not be visibly rotating because the inner ColorRect doesn't get re-centered around its own midpoint. `pivot_offset` is set on the OUTER node but the inner isn't pivot-aware.
  - **Tint sliders** should work — `_visual.modulate` propagates to children.
  - **Reroll Seed** does rebuild — confirms `_regenerate` runs.
  - Next step: capture-and-look to confirm WHICH sliders look broken, then surgical fix per knob.
- [ ] **Update UI** to match the actual asteroid system knobs (after the fix lands).

## Already-done (since this list was captured)

- Wave editor with full CRUD + playtest + state persistence.
- Movement Pattern Editor + Shoot Pattern Editor (reflection-driven, live preview).
- Weapon Editor (Mk slider, DPS readout, tracer preview).
- HD viewport pattern (`Window.content_scale_size` swap) for text-dense dev pages.
- Wave Editor → pattern editor round-trip via `pattern_editor_return_scene` meta.
