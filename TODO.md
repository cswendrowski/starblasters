# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

## Controls + Player

- [ ] **Rebind to genre conventions.** Z = primary, X = bomb/super, **Shift = focus** (reclaim from `shoot_nose`), C or A = secondary, Q/E for weapon swap. Keep Space/WASD aliases for non-shmup players. Ship a settings UI for arbitrary rebinding.
- [ ] **Focus Mode.** Hold focus → player speed × ~0.55. Pair with a small hitbox dot at player center (only visible when focused). Touhou/Cave convention.
- [ ] **Autofire toggle.** A keybind (or settings checkbox) that latches "primary fire" on without needing to hold. Many PC shmup players prefer it.
- [ ] **Gamepad support.** D-pad/stick → move, A → fire, X → bomb, hold-Y → focus, RB → secondary. Settings remap supported.

## Weapons + Parts

- [ ] **Shuffle to Primary / Secondary / Super categories.**
  - Primary (CANNON, hold `shoot`): Energy Blaster, Heavy Blaster, Laser Beam, Machinegun, Wave Gun (+ new Spread Cannon).
  - Secondary (HARDPOINT_WING, hold `shoot_secondary`): **Seeking Missile** and **Rocket Pod** move here from CANNON — they were always supplements masquerading as primaries.
  - Super (DEVICE_BAY_1, tap `shoot_super`, charges per run, refill at outposts): all new.
- [ ] **Build missing weapon types.**
  - **Spread Cannon** (primary) — 3-way / 5-way forked bullets. Mk scaling adds bullets.
  - **Smart Bomb** (super) — screen clear, bullet-cancel, heavy damage.
  - **Hyper Mode** (super) — ~3 s supercharged primary + brief i-frames.
  - **Drone Swarm** (super) — spawn 4-6 autonomous drones for ~5 s.
  - **Phase Shift** (super) — ~2 s invulnerability + bullet-cancel.
  - Optional: **Side Pods**, **Drone Bits** (secondary supplements in HARDPOINT slots).
- [ ] **Wire weapon editor for the new classes.** Filter the list by slot_type so the editor can show primaries / secondaries / supers as separate tabs (or a slot picker). Add resources/weapons subdirs per category.
- [ ] **Touhou death-bomb hook.** On fatal hit, if a super charge is available, consume it and grant i-frames instead of dying.
- [ ] **Hook PartFactory to load weapons from resources/weapons/.tres.** Currently the weapon editor's saves don't affect in-game balance because PartFactory uses script defaults.

## Onboarding

- [ ] **Update onboarding to teach new keybinds + Mk system.** Currently silent on Mk scaling. Need a short panel: "Parts have Mk.1–9; higher Mk = more damage / faster / etc. Mk values are stamped on the part card."

## Dev Menu Cleanup

- [ ] **Remove buttons:** Test Bed, Movement Test, UI Designer, Wave Tester (and the V2 path it drives — `WaveGeneratorV2` likely needs deletion too).
- [ ] **Merge Ship Sizer + Shipyard → unified Shipyard.** Edit any ship / enemy: stats (HP, bounty, speed, hitbox), sprite, scale, orientation flip. Should be the one tool for unit authoring.
- [ ] **Merge Test Level + Test Hazard + Boss Fight → unified "Test Combat" launcher.** One menu with three picker rows: pick wave/level (.tres dropdown), pick hazard (minefield/asteroid_field), pick boss (commander/reaver/sentinel). Single "Launch" button.

## Asteroid Lab

- [ ] **Fix slider wiring.** First-pass investigation:
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
