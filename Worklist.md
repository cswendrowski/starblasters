# Worklist

_Cleaned 2026-06-11: completed items removed, only open tasks remain. The bulk of the
prior Worklist landed across the 2026-06-11 sessions and was verified done in code —
Focus-mode 1px teal hitbox + trail, blaster + primary two-slot model, clear/run-end
screen unification (size sections + codex sprites), faction-glitter coloring, sector-map
codex button, signal-event POI backdrop, wreck-layer feedback (all 5), asteroid spacing /
roundness / dust-trail / dusty-shatter, damage-tell marker randomization, muzzleflashes
(incl. pulse laser), minigun / quad-laser / pulse-laser / dissolve-burn weapons & shaders,
player engine trails, main-menu version label, hangar corner-fx guard. Those are NOT
re-listed here._

_Everything built this session still wants an in-game **eyeball pass** (clear screen,
ember-debris sweetener, torch tuner, shield tuner, faction glitter, asteroid Shader-Lab
mode, supremacy-push spacing)._

---

## Big / playtest-gated

- **Recycler — Pillar 2 (roster migration).** Not started. RecycleController step-2 (timing/look
  owner, zero-regression defaults) + the recycle dev tuner exist; the deep refactor remains —
  generalize edge-detection out of `enemy_base`, NONE-mode opt-in, `enemy_base` delegation,
  MidDepthPresentation shader-tint swap. Regression surface = the whole enemy roster →
  playtest-only. Spec: `docs/recycling_system_pillar2_2026-06-04.md`.

- **Supremacy Push globbing.** Core anti-glob (`_anchor_stagger_y`, descending cruisers) +
  the horizontal-cross overlap fix (Gap 1, height-aware crosser stagger) have landed —
  **playtest these first.** Remaining = **Gap 2**: make cruiser lane *selection* active
  (prefer a lane whose neighbours are clear, via `lane_traffic.is_lane_free`/`free_adjacent`)
  instead of the current passive vertical-queue. Feel-dependent. (`director.gd`)

- **Mine Hazards → 300-enemy mark.** Dense and dangerous: numerous tight waves the player
  weaves through or shoots their way through; bomblet clusters viable; increase per-lane mine /
  bomblet density (this is a place we can relax or ignore the on-screen enemy limits). Also add
  mine sprites into the near/mid parallax layers as decoration — with their pixel pulse light,
  dimmed — as dressing, not live enemies. (`levels_v2.gd` minefield + `director.gd`)

## Shaders / VFX

- **Burning Smoke (from explosion frames).** Built (Shader Lab → Explosions → "Streak Burning
  Smoke") but reads as discrete fiery blobs. **Approach call needed:** keep the segmented-atlas
  comet (tighter overlap + a real lit backdrop) or pivot to a smoother gradient-trail.

- **Smoke sprite won't accept dark color.** Root cause: `graphics/effects/smoke_pulse.png` is
  near-empty faint outlines — not enough opaque coverage to tint dark (the "additive blend"
  hypothesis was wrong; the strip is MIX). Needs a denser 12-frame billow strip. Preview-only
  (the smoke trail isn't used in gameplay yet).

- **Smoke orient-to-motion.** The bottom-toward-motion angle is wrong on screen (sign /
  convention). Make the orient offset a tunable knob in Shader Lab → Smoke, dial it, then bake.

- **Ember variant (Smoke).** Don't begin fading the OLDEST part of the sprite until it has
  reached the END of its travel lifetime (lifetime-vs-distance decoupling in the emitter).

- **Glow-halo redundancy (eyeball).** With the raised HDR glow threshold + HDR-bright bullet
  cores, the per-object diffuse halo on bullets/engines may be redundant — try removing it and
  eyeball-compare; drop it if the env bloom reads well enough.

## Weapons

- **Dev bullet-speed editor.** In the most suitable dev tool, adjust enemy bullet speeds in
  absolute **rung** terms (1–8 = 60–480 px/s, snapped via `Clarity`) and **save** them to the
  `data/bullets/*.tres`. (The Enemy Bench today only has a relative ×-multiplier per enemy.)

- **Codex armory label.** Rename the "Primary Cannons" category header (`enemy_codex.gd:58`) to
  "Blaster" — the only user-facing "Cannon" string left after the shop/manage-ship rename.

- **DPS report + `weapon_stats.csv`.** Both predate Shredder + Pulse Laser — regenerate to
  include them. Then the (report-only) rebalance decision: Energy Blaster is top DPS (120 @ Mk9)
  as the *free* fallback, Minigun far too weak (25, dmg 1), Autocannon scales backwards.

## Renderer (report-only levers — eyeball)

- Forward+ polish levers from `docs/renderer_audit_2026-06-11.md`: `glow_hdr_threshold` tune,
  color-grade strength (contrast 1.08 / saturation 1.12), gate heat-haze (D1) to thrust-only,
  and push more FX into HDR-additive so they bloom (shield ring, beam cores, super flashes).
  All eyeball calls, none applied.

---

## New feedback (add below)
### Shaders:
Ripple Shader: Effect still on player, retire the ripple effect shader from play entirely. It's not working.
Torch Tuner: This is actually "tuning" the shield hit particles, not the torch shader.
Burn Away: shader not picking up the color.
Hex Shield Exploration: Can we have it be other shapes than round? Could we have it be a capsule shape to surround longer enemy sprites if necessary?
Fire Ember Debris: Looks good, but let's use the damage smoke here as well, rather than a puffy orb based one. Let's also attach the torch effect to it, and have it angle with respect to the direction the debris is going, and have it burn out just before the piece fully disintegrates. Also randomize the burn duration for each piece from 1.25 to 2.0.  For these pieces we can also have the damage shader randomize sensitivity from 0.25 to 0.8 and have the max strength up at 0.95.
Streak Burning Smoke: Make sure the sprites are receiving random rotation when being spawned to create additional variation, and fading out as they get older.
Player Damage Effects: The effects need to start once the player has reached 50% of their max hp, and that needs to be their current max, with or without hull modifiers. Right now if the player has a higher max hull than normal, it will start the damage effect sooner than half. This isn't necessarily bad, but it isn't what we want.
Asteroid Drift: Remove the trail and start over with a noise-based smoke trail effect that is the same color as the asteroid itself, and is leaving behind 1px debris as well as it goes. The debris should be in a brightness range around the core asteroid color.
Asteroid Explode: Remove the starting asteroid, replace it with 3-6 new random asteroids of the same color but new shapes. These asteroids should have some spin to them, and disperse in a cone in the direction the asteroid was traveling and should fade into the wreck layer and leave the map at the bottom at the same speed as the destroyed asteroid. The debris pixels are good, but make them all just 1px, and give them some brightness variation/jitter so they look like they are moving. Also make the dust streaks longer and fade out their tails as they go.
Damage Shader: Needs to be pulled back to stay inside the left panel, and overrun the play space, and should be a slightly slower pulse. Should also be a mix color style if it's not already, so it places nicer with the hud elements. The DANGER sprite needs to flash/pulse at the same rate as the warning shader.
### Minefield Hazard
- Mines and bomblets in the background need to use the new art, not old mine art.
- The flashing red light of the mine needs to be more of a in-out pulse than gets faster the closer it is to a player.
- Mines in background layers should not have pixel outlines. They are also rendering with black boxes.
- Bomblets need to just come in dense walls, not arrive on wiggling descents. This is probably a carryover from the cluster mine behavior which we want to remove.
### Nebula
The current nebula effect looks terrible and needs to be retired or removed.
### Sector Map
The vertical spacing on codex/options is nice, please set the outpost/manage buttons to be the same.
signal event backgrounds should also pick up things like asteroids if that's where the signal event is.
### Audio
Sometimes, mostly against corpo waves, the audio abruptly stops then starts over. It's only when a round starts.
### Weapons
Swarm Launcher
- When firing, take the total number of projectiles to be fired, and fire one toward the left and right wing muzzle marker with a 1 frame pause between each salvo until all projectiles have been fired. This should create a sort of fan effect when they fire.
- Swarm projectile hits should use the circle explosion style, just one explosion (lot multiple/layered) and without debris.
Shredder
Give it the autocannon muzzleflash, smoke and shell casing effects.
Have the bullets start white, then turn yellow, orange and red as they reach the end of their lifespan. The shredder bullets should decay after each frame of movement.
Pulse Laser
Give the laser an outer glow of #0012ff and retain the inner line color pogression as it fires.
Give it the blue laser muzzle flash.

### Patterns
Drift_X and Loiter_X movement needs smoothing/inertia when reaching the jiggle point, they stop very sharply. Unless the unit itself wants to handle this based on its size/weight scale. At this point the pattern isn't responsible for smoothing motion, and we instead have a unit-based inertial/turn smoothing setup.
Lane Shift/Drift patterns need guards to keep them from drifting out of the combat area if they are on the outer lanes. Instead they need to always choose an inner lane.
Side_traverse needs to be replaced with/expanded into high/mid/low variants.
Omni_beeline needs to respect persistence trait and eventually leave if it's failed a certain number of passes.