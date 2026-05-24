# Starblaster — Enemy Bullet Library Design

**Branch:** horizontal-rework. Internal viewport 480×270, gameplay band X 132–348. Currently all enemy fire uses one scene (`scenes/projectiles/enemy_bullet.tscn`).

## 1. Current state & case for change

**What exists today:**
- `scripts/projectiles/base_bullet.gd` — unified `BaseBullet : Area2D`. Exports `speed`, `damage`, `velocity_dir`, `max_lifetime`, `guided`, `impact_kind`, `impact_color`, `target_group`. Default `speed=1400` (legacy vertical playfield), `damage=1`, `max_lifetime=5`. Linear motion only.
- `scenes/projectiles/enemy_bullet.tscn` — one scene. 16×16 atlas sprite, 6×6 hitbox, additive magenta `Glow` halo.
- Shoot patterns all point at the same `enemy_bullet.tscn`.

**Case for change:** every enemy looks the same in flight. Bullet identity is the player's primary at-a-glance threat read. A library lets one enemy class feel different between sectors (early Weaver fires Basic, late Weaver fires Plasma Orb) without changing the enemy's logic.

## 2. Proposed bullet roster

Seven variants. Basic at 220 px/s crosses the 216-wide gameplay band in ~1.0s — a fair default dodge-window.

| # | Name | Speed | Dmg | Lifetime | Hitbox | Behavior | Visual |
|---|------|------:|----:|---------:|-------|---------|-------|
| 1 | **Basic** | 220 | 1 | 4s | 6×6 | dumb straight | small magenta pellet w/ animated 4-frame glow (current asset) |
| 2 | **Aimed Sniper** | 300 | 1 | 3s | 4×6 | dumb straight (pattern aims) | thin cyan tracer, 2×8, faint trail |
| 3 | **Heavy Slug** | 160 | 2 | 5s | 10×10 | dumb straight, brief telegraph flash at spawn | fat orange shell, 12×12, additive core |
| 4 | **Spread Pellet** | 200 | 1 | 3s | 5×5 | dumb straight | tiny yellow dot, 4×4, no glow |
| 5 | **Plasma Orb** | 180 | 1 | 4s | 8×8 | sine wobble ±8 px @ 3 Hz lateral to dir | green orb, 10×10, soft halo, slow pulse |
| 6 | **Tracker** | 200 | 1 | 2.5s | 6×6 | turns toward player at 90°/s (cap), lifetime-limited so it can be outrun | violet diamond, 8×8, particle trail |
| 7 | **Burst Round** | 280 | 1 | 1.5s | 5×5 | dumb straight, very short life (fades alpha 0 in last 0.3s) | red streak, 3×10, no glow |

**Sound:** distinct SFX only for the three loud roles — Heavy Slug (low thud), Plasma Orb (electric whine), Tracker (high warble). Rest share the common blip.

**Tracker turn rate:** 90°/s (faster than the brief's 15° — at 480×270 with 200 px/s, 15° would barely curve). 2.5s lifetime keeps it a tease.

**Hitbox philosophy:** per CLAUDE.md "enemies = full sprite size." Same here — never inflate for difficulty. Heavy Slug is genuinely bigger and gets a bigger hitbox honestly.

## 3. Resource architecture — hybrid (data + behavior hooks)

- **One `BulletVariant` Resource** holding data: `speed`, `damage`, `lifetime`, `hitbox_size: Vector2`, `sprite: Texture2D` (or `SpriteFrames` if animated), `glow_color`, `impact_kind`, `impact_color`, `sfx`, and behavior knobs `homing_rate: float = 0.0`, `wobble_amplitude: float = 0.0`, `wobble_frequency: float = 0.0`, `telegraph_flash: bool = false`, `trail_particle: PackedScene`.
- **Enhanced `BaseBullet` script** reads the variant and applies. Wobble/homing/telegraph live as zero-default hooks so Basic pays no runtime cost.
- **Per-variant scripts only when needed** (e.g. future split-on-death). All starter variants are pure data.

**File layout:**
- `scripts/projectiles/bullet_variant.gd` — `class_name BulletVariant extends Resource`
- `data/bullets/basic.tres`, `aimed_sniper.tres`, `heavy_slug.tres`, `spread_pellet.tres`, `plasma_orb.tres`, `tracker.tres`, `burst_round.tres`
- `scenes/projectiles/enemy_bullet.tscn` stays as the ONLY enemy bullet scene; exports `variant: BulletVariant` and applies in `_ready()`.

**Shoot pattern integration:** `shoot_pattern.gd` keeps `bullet_scene: PackedScene` (still the single scene) and gains `bullet_variant: BulletVariant`. Patterns assign the variant on spawn before `start()`. Missing variant → falls back to `basic.tres` so old data still works.

## 4. Migration plan

1. **Author `BulletVariant` resource** + extend `BaseBullet` to consume it. Zero-default all behavior knobs so omitting a variant matches current behavior.
2. **Define `basic.tres`** mirroring today's `enemy_bullet.tscn` exactly. **Parity test**: a Skirmisher firing through `single_shot` with `bullet_variant = basic.tres` should be indistinguishable from today.
3. **Add the other six variants** as `.tres` only — no enemy gets them yet.
4. **Update the four shoot patterns** to optionally carry a `bullet_variant` and apply it on spawn.
5. **Sprite pass** (APT delivers assets per §5).
6. **Re-tune per-enemy mapping** as a separate PR: Skirmisher → Aimed Sniper, Cutter → Burst Round, Bulwark turret → Heavy Slug, Weaver → Plasma Orb, Hunter → Tracker, swarm trash stays on Basic, spread enemies → Spread Pellet.
7. **Boss primitives** — leave `fire_aimed_burst` / `fire_ring` on Basic for the initial cutover; revisit per-boss in a follow-up.

## 5. Sprite list (APT deliverable)

Eight assets total: seven variants plus an optional Tracker trail particle. **Pixel-art style, nearest filter**. Bullets must read at 480×270 — anything below 4 px wide vanishes on motion.

| File | Size (px) | Frames | Palette / color | Description | Reuse? |
|------|----------:|-------:|-----------------|-------------|--------|
| `bullet_basic.png` | 16×16 atlas, 4 frames | 4 | magenta/white core | Animated pellet, additive glow. Current art. | **Reuse** `Mini Pixel Pack 3/Projectiles/Enemy_projectile (16 x 16).png` |
| `bullet_sniper.png` | 8×8 atlas, 2 frames | 2 | cyan #4FF, white core | Thin vertical tracer, sharp tips, faint blur trail. | New — or recolor `tracer-yellow.png` to cyan |
| `bullet_heavy_slug.png` | 16×16, single | 1 | orange #F80, dark red rim | Fat round shell, 12×12 visible, dark outline. Heavy & slow read. | Possibly recolor `blaster_heavy.png` |
| `bullet_spread.png` | 8×8, single | 1 | yellow #FE4 | Tiny 4×4 dot, no glow. Cheap & abundant. | Possibly `Player_square_shot` recolor |
| `bullet_plasma.png` | 16×16, 4 frames | 4 | green #4F8, soft cyan halo | Round 10×10 orb, slow pulse animation. | New — could derive from `Player_charged_donut_shot` |
| `bullet_tracker.png` | 12×12, 2 frames | 2 | violet #A4F, white core | Diamond shape (rotated square), wobbly outline frames. | New |
| `bullet_burst.png` | 16×16, single | 1 | red #F33 | Streak shape — 3×10 vertical line w/ tapered tip. No glow. | New — possibly recolor `tracer-large-yellow.png` |
| `tracker_trail.png` | 4×4, single | 1 | violet, alpha gradient | Particle for Tracker trail. | New, trivial |

**Reuse summary:** Basic confirmed reusable. Sniper / Heavy Slug / Spread / Burst could be recolors of existing assets — audit `graphics/projectiles/` per-sprite. Plasma Orb, Tracker, and tracker_trail need fresh art (5–6 unique creates).

**Important:** all bullet sprites must be **rotation-neutral or authored pointing "down"** — `BaseBullet.start()` already rotates to `velocity_dir.angle() + PI/2`, so sprites authored facing down rotate correctly into any pattern direction.

## 6. Open questions

1. **Sound per variant?** Proposal: only Heavy Slug / Plasma Orb / Tracker get distinct SFX; rest share the common blip. Confirm or expand?
2. **Wave-gen override:** should `WaveGeneratorV2` carry a `bullet_variant_override` knob (force all enemies in a wave to fire X variant for a themed wave)? Recommendation: read from the entry by default; add the override only if themed waves land.
3. **Roster mapping ownership:** bake variant into the **shoot pattern .tres** (so `aimed_fire_sniper.tres` literally is "aimed_fire + sniper") or into the **enemy entry**? Recommendation: shoot pattern .tres — encourages thinking of shoot patterns as full behaviors.
4. **Boss reuse:** `boss_base.fire_aimed_burst` / `fire_ring` primitives. Proposal: add optional `bullet_variant` param defaulting to Basic. Reaver could fire Heavy Slug rings; Sentinel could spawn Trackers in P2.
5. **Player bullets:** out of scope. Player bullets already have multiple scenes tied to Parts. Could retro-fit to the same Resource later.
6. **Mk.N scaling on enemy bullets:** no new per-variant scaling needed; sector multiplier already handles damage scaling player-side.

---

**Relevant files:**
- `scripts/projectiles/base_bullet.gd`
- `scenes/projectiles/enemy_bullet.tscn`
- `scripts/enemies/shoot_patterns/*.gd` (single_shot, aimed_fire, spread_shot, burst_shot)
- `graphics/projectiles/` (audit for reuse)
- `Mini Pixel Pack 3/Projectiles/` (atlas source for Basic, possible reuse for others)
