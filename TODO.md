# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

## Controls + Player

- [x] **Rebind to genre conventions** — `5d36dcc`. Z+Space = primary, C = secondary, X = super, Shift = focus, Q/E weapon swap. Settings remap UI still TODO.
- [x] **Focus Mode** — `5d36dcc`. Hold Shift → speed × 0.55 + hitbox dot at player center.
- [ ] **Settings remap UI.** Currently keys are hardcoded in project.godot. Players can't rebind without editing the .godot file.
- [ ] **Autofire toggle.** A keybind (or settings checkbox) that latches "primary fire" on without needing to hold. Many PC shmup players prefer it.
- [ ] **Gamepad support.** D-pad/stick → move, A → fire, X → bomb, hold-Y → focus, RB → secondary. Settings remap supported.

## Weapons + Parts

- [ ] **Shuffle Seeking Missile + Rocket Pod to HARDPOINT_WING.** **BLOCKED**: requires `fire_secondary()` pipeline first — separate `secondary_bullet_scene` / `secondary_cooldown` / `secondary_ammo` fields + own timer, since their `apply()` currently writes to the primary fields. Order: wire secondary fire pipeline → then move the parts.
- [x] **Spread Cannon** — `83cd9f5`. Fans bullets across an arc, Mk scaling adds bullets (Mk.1=3 → Mk.4+=9 capped). `player.gd::fire_primary` honors `bullet_spread_count` / `bullet_spread_degrees`.
- [x] **Smart Bomb** — `b9e3458`. First super weapon. Screen-clear + heavy damage on every enemy. Mk scales damage + charges. Auto-equipped Mk.1 in DEVICE_BAY_1 on starting loadout. `fire_super()` wired.
- [ ] **Hyper Mode** (super) — ~3 s supercharged primary + brief i-frames.
- [ ] **Drone Swarm** (super) — spawn 4-6 autonomous drones for ~5 s.
- [ ] **Phase Shift** (super) — ~2 s invulnerability + bullet-cancel.
- [ ] **Side Pods / Drone Bits** — secondary supplements in HARDPOINT slots.
- [ ] **Outpost refill for super charges.** Smart Bomb starts each run with full charges; spent charges don't refill on shop visits yet.
- [ ] **HUD indicator for super_charges.** `super_charges_changed` signal is emitted; nothing reads it. Need a charge pip strip somewhere visible.
- [ ] **Filter Weapon Editor list by slot_type.** Now that DEVICE_BAY + (eventually) HARDPOINT parts are in `resources/weapons/`, the editor should show category tabs (Primary / Secondary / Super) instead of one flat list.
- [ ] **Touhou death-bomb hook.** On fatal hit, if a super charge is available, consume it and grant i-frames instead of dying.
- [ ] **Hook PartFactory to load weapons from resources/weapons/.tres.** Currently the weapon editor's saves don't affect in-game balance because PartFactory uses script defaults.

## Onboarding

- [x] **Update onboarding to teach new keybinds + Mk system** — `57faad3`. Controls page now lists Z/C/X/Shift. New Parts & Marks page explains Mk.1–9 scaling.

## Dev Menu Cleanup

- [x] **Remove obsolete buttons** — `35a66a2`. Test Bed, Movement Test, UI Designer, Wave Tester gone. `WaveGeneratorV2` still on disk; pull when nothing references it.
- [ ] **Merge Ship Sizer + Shipyard → unified Shipyard.** Edit any ship / enemy: stats (HP, bounty, speed, hitbox), sprite, scale, orientation flip. Should be the one tool for unit authoring.
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
