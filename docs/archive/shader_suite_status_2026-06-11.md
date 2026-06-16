**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: historical status snapshot.
Kept for design history; do not cite as the live spec.

# Shader suite (#44) — status audit + handoff (2026-06-11)

#44 is 8 visual sub-items. Per CLAUDE.md these are **human-iterated, capture-loop**
work — agents must not edit-capture-look. A parallel shader session already built a
lot of the infrastructure (the task itself warned "another session did shader work;
check current state first"). This doc audits each sub-item against the **current
code** so Roman can verify with captures instead of an agent churning blind. One
safe, unambiguous code fix landed this pass (item 3); the rest are flagged
DONE-ish / NEEDS-EYE / TO-BUILD.

## Sub-item audit

**1. Engine trails missing on player ship — WIRED, needs visual confirm.**
`player.gd:457-464` finds every `Engine*` Marker2D and attaches `engine_trail_fx`
(blue #00d3ff). All three combat ship scenes have the markers (`player.tscn`:
`Engine`; `player_b/c.tscn`: `EngineL`+`EngineR`) plus a `GlowMask`. The trail's
world-space parenting bug (the SubViewport upper-left-corner regression) was fixed
this session in `engine_trail_fx.gd` (`enemy.get_parent()`). So the trail should
render in combat now — **Roman: confirm the blue plume appears behind the ship in a
real patrol.** (`player_drone.tscn` has no engine markers by design — no trail.)

**2. Smoke shader orient-to-motion — likely DONE in `smoke_trail_fx.gd`.**
`smoke_trail_fx.gd` (shader-session build) has an `orient` knob ("rotate the
sprite's bottom toward the source's motion") with per-frame `angle_min/max`
rewriting + `jitter_deg`. If orient still reads broken, the bug is in that per-frame
angle math (around the emitter's velocity→angle step), not a missing feature.
**Roman: capture a moving smoke source; if the puffs don't trail the motion, file
the specific direction it's wrong.**

**3. Smoke sprites read gray (not accepting color) — FIXED (shader) this pass.**
`graphics/billow_smoke.gdshader` overwrote `COLOR` with `smoke_color` outright,
ignoring the node's per-instance modulate — so every puff read the flat default
gray. Now multiplies by the incoming modulate:
`COLOR = vec4(smoke_color.rgb * COLOR.rgb, alpha * smoke_color.a * COLOR.a)`.
Default white modulate → byte-identical to before; callers can now tint a puff by
setting its `modulate`. (Note: `smoke_trail_fx.gd` is GPUParticles with
`start_color`/`end_color` and already accepts color independently — this fix covers
the billow-shader ColorRect/Sprite path used by `shader_lab` + any future sprite
puff.)

**4. Dissolve burn shader: color tuning + burn-from-marker — TO-BUILD.**
`graphics/pixelated_burn.gdshader` does center-out dissolve. Needs (a) a tunable
burn/ember color uniform, and (b) a burn-origin uniform (vec2 in UV space) so the
dissolve can start from an engine/turret/missile marker instead of always center.
Scope: one shader uniform + the caller passing the marker's local UV. **Best done
with the capture loop** so the burn edge color reads right.

**5. Ember Smoke variant: don't fade oldest until end of travel lifetime — NEEDS-EYE.**
The ember-smoke lifetime should hold the oldest puff until it reaches the end of its
travel, not fade it on a fixed timer. Check `ember_fx.gd` / `smoke_trail_fx.gd`
lifetime-vs-distance coupling. Tunable via `shader_lab` (the shader session added
ember ramp controls there).

**6. Explosion sweetener: debris-with-damage-shader variant — TO-BUILD (biggest).**
A debris-chunk variant that carries the damage/burn shader + trailing ember sparks
(`ember_fx.spray`) + a damage-smoke trail, and slowly disintegrates via the burn
shader before freeing. Composes existing pieces (`ember_fx`, `pixelated_burn`,
`smoke_trail_fx`) onto a drifting debris sprite — closest cousin is
`dust_fragment.gd` (this session's asteroid-shatter chunk). **New VFX; build with a
capture harness.**

**7. Burning Smoke sprite from explosion frames — TO-BUILD (needs asset).**
A smoke sprite sampled from the explosion sprite-sheet frames (first frame = fresh
start, last = dissipating tail). Needs the explosion atlas wired as the smoke
texture source. Asset-dependent.

## What landed this pass
- `graphics/billow_smoke.gdshader`: respect node modulate (item 3). Zero-regression.

## Recommended next session (with Roman at the wheel for captures)
1. Confirm 1 + 2 by capture (may already be done → close them).
2. Item 3 is in; verify a tinted puff.
3. Build 4 (small) → 5 (tuning) → 6 (compose) → 7 (asset) in that order, each
   through `tools/capture_<mechanic>.gd` → GIF → review.
