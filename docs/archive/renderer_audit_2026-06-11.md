**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: historical Forward+ audit (glow_hdr_threshold is now 1.5; bullet glow halos were removed).
Kept for design history; do not cite as the live spec.

# Renderer audit — Forward+ vs Compatibility (2026-06-11)

What the Forward+ pivot unlocks for a 480×270 pixel shmup, what's already leveraged, and the open polish
opportunities. Report only — recommendations not applied except where noted.

> **STATUS 2026-06-12:** levers **A + B are LIVE** in main.tscn — `glow_hdr_threshold = 1.0` (A) and
> `adjustment_enabled` with contrast 1.08 / saturation 1.12 (B). This doc's "Current state" below
> (which says threshold 0.0) is stale. Lever **C** is partly done: muzzle/explosion FX are HDR-bright
> (1.9 / 2.1) and bullets now self-modulate into HDR (`base_bullet.BULLET_HDR_GAIN`, after the
> glow-halo removal); shield ring / beam cores / super flashes still want a >1.0 additive pass.
> Lever **D** (heat-haze / screen-ripple) unstarted.

## Current state (project.godot `[rendering]` + main.tscn)
- `rendering_method` = **forward_plus** (the line is dropped → engine default Forward+; Windows-only build).
- `viewport/hdr_2d = true` — 2D renders in a linear RGBA16F buffer; additive blends accumulate in HDR and
  values >1.0 survive for bloom. *(The SubViewport HDR-parity fixes this session keep dev play-areas in sync.)*
- `2d/snap/snap_2d_transforms_to_pixel = true` + nearest filter (`default_texture_filter = 0`) — pixel-art crisp.
- **2D glow IS already enabled** (main.tscn `Environment_glow`): `glow_enabled=true`, intensity 0.8, strength
  0.7, **`glow_hdr_threshold = 0.0`**.
- Screen-reading shaders in use: `black_hole`, `screen_glow` (`hint_screen_texture`).

## What Forward+ gives us that Compatibility did not
1. **Full 2D glow/bloom pipeline** — Compatibility's glow is limited/absent; Forward+ runs the real
   multi-pass bloom. Combined with `hdr_2d`, bright additive pixels (muzzle flashes, bullet glow halos,
   lasers, explosions, the electric-ball) can bloom for free. **This is the headline win** and it's already on.
2. **HDR additive accumulation** — additive FX no longer clip at 1.0; overlapping bullets/explosions build
   genuine brightness that the glow pass then blooms. (Already exploited by the glow_halo / electric shaders.)
3. **`hint_screen_texture` / screen-space distortion** — reliable under Forward+ (black-hole lensing,
   screen_glow). Compatibility's screen-copy is flakier. Room to expand (heat-haze, shockwave ripple).
4. **WorldEnvironment post** — glow + **color adjustments** (brightness/contrast/saturation) + tonemapping
   are available as a cheap full-screen grade. Currently only glow is used.
5. **Better blend modes, MSAA, float render targets, compute** — mostly irrelevant for nearest-filtered 2D
   pixel art (MSAA would fight the pixel grid), but the float targets are what make (1)+(2) work.

## Findings / opportunities

**A. `glow_hdr_threshold = 0.0` blooms EVERYTHING (recommend ~1.0).** At threshold 0 every lit pixel — hulls,
UI, backdrop — feeds the bloom, which softens the crisp pixel-art read and can wash mid-tones. For pixel art
you want **only the HDR-bright additive FX** (which exceed 1.0 in the HDR buffer) to bloom. Raising
`glow_hdr_threshold` to ~1.0 (and nudging additive FX brightness up where needed) keeps hulls razor-sharp
while muzzle/bullet/explosion glow still blooms. **Low-risk, high-impact — the single best tuning lever.**
*(Left for Roman to eyeball-tune; it interacts with every additive shader.)*

**B. Add a subtle color grade.** The `Environment` already exists — enabling `adjustment_enabled` with a
gentle contrast/saturation bump (or a small `adjustment_color_correction` LUT) gives the whole game a graded,
less-flat look at ~zero cost. Tasteful and reversible.

**C. Push more FX into HDR-additive so they bloom.** Anything that should "glow" (shield ring, engine torch
tips, firecore, beam cores, super flashes) should use additive blend with brightness >1.0 so the glow pass
catches them. Audit each FX for `BLEND_MODE_ADD` + a >1.0 colour.

**D. Screen-space sweeteners now affordable.** Heat-haze behind engine exhaust, a screen-ripple on big
explosions / boss slams, chromatic-aberration on damage — all `hint_screen_texture` effects that read well
under Forward+ and were impractical on Compatibility.

**E. Don't chase MSAA / TAA.** They fight the snapped pixel grid; keep nearest + snap. The pixel-art identity
is correct as-is.

## Bottom line
The heavy lifting (Forward+, hdr_2d, 2D glow) is already in place. The biggest immediate gain is **tuning
`glow_hdr_threshold` up off 0.0** so bloom is reserved for bright additive FX instead of the whole frame. After
that, a light color grade (B) and pushing the remaining glowy FX into HDR-additive (C) are the best
incremental polish. Screen-space sweeteners (D) are the stretch goals.
