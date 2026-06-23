# Faction energy recolor — unified grayscale bullets & muzzles

**Status:** SCOPED / NOT BUILT — engine side waits on Roman's grayscale assets. The faction color
data it rides on (`Factions.MUZZLE_GLOW_COLOR`) already exists and ships.

**Date:** 2026-06-22 · **Author:** Claude (with Roman)

## Goal

Stop authoring a separate colored bullet/muzzle sprite per faction. Instead author **one grayscale
sprite per projectile SHAPE** and recolor it per faction at render time, off the already-centralized
per-faction energy color. Same for muzzle flashes. This collapses ~16 colored sprites + a per-faction
scene-swap down to ~4–6 grayscale sprites + a one-line tint, and it makes "recolor a faction" a single
data edit instead of a re-export.

This only touches **enemy** bullets + muzzles. Player projectiles keep their own look.

## Why this is a small engine change (it fits the existing glow pipeline)

The bullet glow is **not** painted into the sprite — it's the WorldEnvironment bloom acting on HDR-bright
pixels. `base_bullet._apply_hdr_bloom()` pushes the bullet sprite's `self_modulate` ×`BULLET_HDR_GAIN`
(1.8) so bright pixels exceed the bloom threshold and glow; transparent edges stay matte. The per-variant
`glow_color` field is already **vestigial / not read** (`base_bullet._apply_variant` says so).

Consequence: **a bullet's glow hue == its sprite's hue.** So:

- A **grayscale** sprite with `self_modulate = faction_color × 1.8` → blooms in the faction hue, for free.
- The brightest (whitest) pixels become the faction color at full intensity → a hot, in-hue core that
  blooms; the falloff is dimmer faction color. That **is** the standard energy-bolt read.

So the recolor is one substitution on the existing HDR-modulate line — no new glow system.

## Current system (what this replaces)

- `BulletVariant` (`scripts/projectiles/bullet_variant.gd`): per-bullet data `.tres` — `static_texture`/
  `sprite_frames`, stats, `family` (`ball`/`bolt`/`laser`/`wave`), and a now-dead `glow_color`.
- `BulletCatalog` (`scripts/projectiles/bullet_catalog.gd`):
  - `scene_for(variant)` → each variant's own indexed `.tscn` (authored sprite + hitbox).
  - `faction_variant(variant, faction)` → **whole-variant swap**: a `family`-tagged variant becomes the
    faction's same-family clone (`_family` table: `ball/bolt/laser/wave → {Zealot: …, Privateer: …}`),
    i.e. a different `.tres` + a different colored `.tscn`/sprite. Corpo/supremacy have no set → fall back.
- `shoot_pattern._spawn_bullet` calls `faction_variant(bv, enemy.get_meta("faction_skin", -1))` then
  spawns the resolved scene.
- Muzzles: `muzzle_fx.play_enemy(world_pos, dir, root)` — one `ENEMY_MUZZLE_STRIP`, additive blend, **no
  color param** (untinted).

So today a faction "skin" = a parallel set of colored sprites + scenes + `.tres` per faction, selected by
swapping the whole bullet. That's the asset burden.

## Proposed design

**One grayscale sprite per shape; tint at spawn off the faction's energy color.**

### Color source (already built)
`Factions.MUZZLE_GLOW_COLOR` (the "energy color", distinct from `LIVERY_COLOR`):
- Supremacy + Zealot → gold `#fbf236`
- Privateer + Corporate → lime `#99e550`

So bullets/muzzles are **paired by color** (priv+corp lime, sup+zealot gold); the *ship livery* is what
visually separates priv from corp. Recolor is via `Factions.muzzle_glow_color(faction)`; `faction` comes
from `enemy.get_meta("faction_skin", -1)` (the director already stamps this on every spawn). `-1` (no
faction / dev) → white = a neutral energy bolt.

### Bullet recolor (engine)
1. Add `var glow_tint: Color = Color.WHITE` to `base_bullet.gd`.
2. `_apply_hdr_bloom()` uses it: `self_modulate = Color(glow_tint.r, glow_tint.g, glow_tint.b, a) *
   BULLET_HDR_GAIN` (keep alpha). White default = today's behavior exactly.
3. `shoot_pattern._spawn_bullet`: instead of the `faction_variant` swap, set the spawned bullet's
   `glow_tint` = `recolor ? Factions.muzzle_glow_color(faction_skin) : Color.WHITE` before `start()`.
4. Gate with `BulletVariant.faction_recolor: bool = true`. Energy bullets recolor; **physical**
   projectiles (missile, rocket, drop_pellet, bomblet) set it `false` and keep their own sprites.
   Special fixed-hue bullets (e.g. a firecore-orange hazard, a boss signature) also `false` (+ their own
   colored sprite, or an explicit `glow_tint`).

### Muzzle recolor (engine)
1. `muzzle_fx.play_enemy(world_pos, dir, root, color: Color = Color.WHITE)` → `flash.modulate = color`
   (it's already additive, so white = unchanged, a hue tints it).
2. Its 5 call sites (`shoot_pattern`, `enemy_turret`, `enemy_rocket`, `enemy_frigate`, `enemy_sword`)
   pass `Factions.muzzle_glow_color(host.get_meta("faction_skin", -1))`. A tiny helper
   (`Factions.muzzle_color_for(enemy)`) keeps the call sites one-liners.

### What retires
- `BulletCatalog.faction_variant()` + the `_family` table.
- The per-faction variants + scenes: `_V_ZBALL/…/_V_PWAVE`, `_S_Z*`, `_S_P*`, and the
  `data/bullets/{zealot,privateer}_*.tres` + `scenes/projectiles/{zealot,privateer}/*` + their colored
  PNGs (`graphics/projectiles/projectile_privateer_*`, zealot bullet art).
- The dead `glow_color` field on `BulletVariant`.

### What stays
- One `BulletVariant` + indexed scene **per shape** (basic/spread/heavy/wave/laser/cannon/diamond/
  tracer) — now pointing at **grayscale** art. `BulletCatalog.scene_for` unchanged.
- `family` stays as metadata (and could drive shape selection later); it no longer triggers a swap.

## Assets Roman authors

Grayscale (luminance-only) sprites — RGB is white→grey, **alpha defines the shape**; the recolor multiply
is the only color source. Give each a **bright (near-white) core** so the modulate yields a hot in-hue
center that blooms, fading to dimmer edges.

- One per energy SHAPE in use: **ball, bolt, laser, wave** (+ whatever size variants the current set has —
  small/large). Match the existing hitbox/scene footprints.
- One grayscale **muzzle-flash strip** (replacing/repainting `enemy_muzzle.png`), same frame layout the
  current `ENEMY_MUZZLE_STRIP` uses.

Note on the core: a single grayscale gives a *faction-hued* core (white×color), not a pure-white one. If a
pure-white core + colored halo is wanted, bake a **2-layer** sprite (white core child that stays white +
a grey glow layer that gets modulated). Decide before drawing; the engine supports either (the core child
just opts out of `glow_tint`).

## Implementation plan (when assets land)

1. Drop grayscale art in; point the per-shape `.tres`/scenes at it (or new scenes). Keep hitboxes.
2. `base_bullet`: add `glow_tint`; fold it into `_apply_hdr_bloom`.
3. `BulletVariant`: add `faction_recolor: bool = true`; set `false` on physical/special variants.
4. `shoot_pattern._spawn_bullet`: drop the `faction_variant` swap; set `glow_tint` from
   `muzzle_glow_color` when `faction_recolor`.
5. `muzzle_fx.play_enemy`: add `color`; tint the flash. Thread `muzzle_glow_color` through the 5 callers.
6. Retire the per-faction catalog entries, scenes, `.tres`, sprites, and `glow_color` (grep clean).
7. Verify (below). Visual pass: capture a priv (lime) vs sup (gold) wave to confirm hue + bloom read.

## Verification
- `parse_check` + headless boot clean.
- Probe: spawn an energy bullet with `faction_skin` = each faction → its sprite `self_modulate` ≈
  `muzzle_glow_color(f) × 1.8`; `faction_skin = -1` → white×1.8. A `faction_recolor=false` bullet stays
  white. `play_enemy` with a color tints the flash.
- Grep: zero references to `faction_variant` / the retired `_V_*`/`_S_*` faction entries / `glow_color`.
- Roman GIF pass: priv/corp waves read lime, sup/zealot gold, cores bloom in-hue, no muddy tints.

## Open questions for Roman
1. **Core look:** single grayscale (faction-hued core) or 2-layer (white core + colored halo)?
2. **Physical projectiles** (missiles/rockets/drop-pellets/bomblets): keep current art untinted — confirm.
   Any of them you DO want faction-tinted?
3. **Pairing is intentional?** Priv+corp share lime, sup+zealot share gold (per `MUZZLE_GLOW_COLOR`), so
   their bullets look identical and only the livery separates them — confirm that's the intent.
4. **Player bullets** stay separate this pass — or fold them in too (off the player livery color)?
