# Handoff — remaining / not-yet-done work (2026-06-11)

Snapshot of everything still open at the end of the `wl-session-2026-06-11` branch, so
the next session (or Roman) can pick up cleanly. Ordered by category; the **Shaders**
block is where the bulk of the outstanding *build* work is.

---

## Shaders — outstanding builds (the big remaining chunk)

### Smoke trail (`scripts/effects/smoke_trail_fx.gd` + `smoke_trail_emitter.gd`)
Currently only previewable in **Shader Lab → Smoke** (not used in gameplay yet).
- **Base-at-emission, not center.** The `smoke_pulse` sprite should anchor its BASE at
  the emission point and billow up from there; right now each particle is centered on
  its position. GPUParticles2D has no per-particle pivot, so this needs an offset
  approach (spawn the particle ~half-a-sprite "up" from the emit point, scaled with
  `scale_grow`), or a custom draw.
- **Orient bottom toward motion — STILL not right.** The emitter rewrites
  `angle_min/max` to `vel.angle() - 90°`, but the on-screen result is wrong. It's a
  **sign/convention bug** (particle `angle` rotation direction vs the sprite's "up"),
  only resolvable by watching the lab's weaving host. Try `+90`, negating `vel`, and
  the `(sin,-cos)` vs `(sin,cos)` basis.
- **Dark colors don't work (can't go black).** Bright tints show, dark/black don't —
  classic symptom of an **ADDITIVE blend** (black adds nothing). Check the
  `CanvasItemMaterial` blend mode used for the strip animation in `_make()`; if it's
  additive, switch to MIX so the `color_ramp` can darken. Also confirm `smoke_pulse.png`
  has enough alpha to register a dark tint (it's faint light-gray outlines today).

### Ember variant: Smoke (`scripts/effects/ember_fx.gd` / smoke variant)
- Don't begin fading the OLDEST part of the sprite until the sprite has reached the END
  of its travel lifetime. (Lifetime-vs-distance decoupling in the ember/smoke emitter.)

### Explosion sweetener — ship-debris variant (NEW build)
- A variant of the ship debris that: carries the **damage shader (randomized)**, trails
  **ember sparks** (use the ember sprite) + **damage smoke**, and **slowly disintegrates
  via the burn shader** — at which point the attached fx (sparks, smoke) are freed and
  end. Closest cousin: `scripts/effects/dust_fragment.gd` (asteroid shatter chunk) +
  `burn_fx.apply_burn` (now supports an origin) + `ember_fx.spray`.

### Burning Smoke sprite — from explosion frames (NEW build)
- Using the explosion sprite frames, make a **streaming fiery smoke** effect: the FIRST
  explosion frame is the start (head), the FINAL frame is the tail. A trail/strip that
  samples the explosion atlas across its length.

### Glow question (Roman asked) — partly answered, needs a look
- The **world-environment glow** (post-process bloom on HDR-bright pixels) and the
  **per-object diffuse glow** (`glow_shader_fx`/`glow_halo` soft halo behind bullets/
  engines) do different things. With the raised `glow_hdr_threshold` + HDR-bright bullet
  cores (halo `INTENSITY` 1.2), the bright cores already bloom via the env glow, making
  the per-object halo **partly redundant** for bullets/engines.
- **TODO:** try removing the bullet/engine halo and eyeball-compare; if the env bloom
  reads well enough, drop it (fewer nodes, simpler). It's a look call, not a clear win.

### Unclear / needs Roman
- The message "**The smoke shader is also not.**" was cut off — the second smoke issue
  is unknown. Clarify before acting.

---

## Weapons — follow-ups / polish

- **Pulse Laser:** needs a real **fire SFX** (currently `FireSfxKind.NONE` →
  `$ShootSound` placeholder, the old `pulse_*` clips were retired). Eyeball: beam glow +
  white→#000fd8 ramp, 7px hit tolerance feel, 0.06s cadence, 320px range.
- **Shredder:** eyeball pellet look/feel; tunable dials are cadence (0.35), pellet speed
  (300), pellet lifetime/range (1.6s).
- **DPS rebalance (report-only, NOT applied)** — see `docs/weapon_dps_report_2026-06-11.md`:
  Energy Blaster is the top DPS (120 @ Mk9) as the *free* fallback; Minigun far too weak
  (25, dmg 1); Autocannon scales backwards (flat dmg). Decide whether to act.
- **`docs/weapon_stats.csv` is stale** — predates Shredder + Pulse Laser; regenerate.

---

## Renderer / FX (report-only levers, not applied)

- `glow_hdr_threshold` is now 1.0 — eyeball-tune.
- Color grade strength (`adjustment_contrast` 1.08 / `adjustment_saturation` 1.12) —
  eyeball.
- **Heat-haze (D1)** is always-on during combat — consider gating to thrust-only.
- Opportunity: push more FX into HDR-additive so they bloom (shield ring, beam cores,
  super flashes). See `docs/renderer_audit_2026-06-11.md`.

---

## Weapon-data centralization — optional follow-up

- A few stat values still live as `@export` **declaration defaults** (schema), not in
  the `.tres` (e.g. wave gun's Mk.9 endpoints, drone counts, spread bullet count). This
  is the standard schema-default + data-override model — NOT the "two competing sets"
  bug, which is fixed. If a **fully-explicit `.tres`** (every stat visible in the data
  file) is wanted, neutralize the declaration defaults + write the values into each
  `.tres`. See `docs/weapon_data_centralization_2026-06-11.md`.

---

## Big deferred builds (playtest / eyeball-gated — deliberately held)

- **Recycler Pillar 2 — roster migration.** The RecycleTuner + RecycleController landed
  (zero-regression). The deeper refactor (generalize edge-detection out of `enemy_base`,
  NONE-mode opt-in, `enemy_base` delegation, MidDepthPresentation shader-tint swap) was
  held — its regression surface is the whole enemy roster and only a multi-pattern
  playtest can clear it. Spec: `docs/recycling_system_pillar2_2026-06-04.md`.
- **Clear/defeat screens — full unification.** The level-clear info (clear-time +
  size-sorted kills) landed; the full 3-screen architecture unification + true
  size-section grouping was deferred as a blind-refactor risk.

---

## Verification owed (built to spec, NOT playtested — "NEEDS ROMAN")

Everything visual built this session was made to spec without a live eyeball. The big
ones to confirm in play / the new labs:
- Damage tells (fire/smoke) now attach to real engine markers + react to max-HP — check
  in **Player FX Lab** (dev menu).
- Per-combat-node faction glitter on the sector map (supremacy red / privateer green /
  corpo blue / zealot purple) + privateer-interloper sprinkle.
- Renderer polish A–D (glow threshold, grade, HDR FX, aberration, danger pulse).
- Dissolve burn-from-marker + colour (Shader Lab → Disintegrate).
- Pulse Laser dispersion + colour ramp; Shredder random shotgun spread.
