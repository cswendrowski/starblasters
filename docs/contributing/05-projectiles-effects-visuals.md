# 05 · Projectiles, Effects & Visuals

This doc covers **bullets and missiles**, **visual effects helpers**, and **the backdrop parallax system**. These are the visual building blocks that make enemies and combat *read* on screen.

**What this is NOT:** If you're wiring enemy fire or player weapons, that's Docs 03–04. If you're adding sound, that's a separate effects pipeline (see `scripts/effects/sfx.gd` and `scripts/effects/weapon_sfx.gd`). If you're tuning colors or visual balance, see Doc 01's section on the iteration workflow.

---

## Projectiles: Bullets & Missiles

Every projectile — player bullets, enemy fire, rockets, missiles — extends one of two base classes.

### `base_bullet.gd` — dumb and guided fire

`scripts/projectiles/base_bullet.gd:1` is the unified base for all gunfire. It's an `Area2D` that:

- Moves in a straight line (or wobbles/homes if the variant requests it)
- Detects collisions with the target group (`"enemies"` for player fire, `"player"` for enemy bullets)
- Handles the unified hit pipeline: white flash on the enemy, `take_hit(damage)` call, impact effect spawn
- Kills itself on lifetime expiry or offscreen bounds
- Never spawns with a hit — it waits for `start(pos, dir)` or direct `global_position`/`velocity_dir` setting before entering `_process`

All bullets export the same base properties:

| Export | Type | Default | Purpose |
|--------|------|---------|---------|
| `variant` | `BulletVariant` | null | Resource that overrides speed/damage/lifetime/visuals. Optional; if null, uses scene defaults. |
| `target_group` | String | "enemies" | Which group this bullet damages. |
| `speed` | float | 1400.0 | Pixels per second. Positive always; direction comes from `velocity_dir`. |
| `damage` | int | 1 | HP to remove on hit. |
| `velocity_dir` | Vector2 | (0, -1) | Unit direction. Rotation is auto-derived (`start()` sets rotation for you). |
| `max_lifetime` | float | 5.0 | Seconds. Kills the bullet if it hasn't hit or left the playfield. |
| `guided` | bool | false | Legacy flag for guided-missile logic (now in `variant.homing_rate`). |
| `impact_kind` | int | 0 | Enum: 0=SMOKE (small bullets), 1=EXPLOSIVE (warheads). See `scripts/effects/impact_fx.gd`. |
| `impact_color` | Color | (1,1,1,1) | The tint that colors the impact flash. Usually matches the bullet's muzzle glow. |

**The critical spawn rule (golden rule #2 from README):** Projectiles **must spawn as children of `get_tree().root`, never as children of the player or enemy.** The shooter `queue_free`s on death and would take all its children with it, orphaning any bullets still in flight. This is enforced in `base_bullet.gd:310–313` — impact effects spawn at the root, not under the bullet.

#### The variant system

A `BulletVariant` Resource lets you override bullet behavior at runtime *without writing a new script.* The variant is applied in `_ready()` (before `_apply_visuals()` runs) via `_apply_variant()` at line 74.

**Important gotcha:** Scene-level exports (e.g. setting `speed = 400` in the `.tscn` inspector) do NOT override the variant. The scene properties are there *for inspection in the editor only.* Once `_apply_variant()` runs, it overwrites them. This is by design — the variant is the runtime source of truth. See `docs/bullet_library_2026-05-24.md` (link it in a real doc build) for the full variant catalog and the resource schema.

#### Subclass pattern: `_apply_visuals()`

Subclasses (e.g. `scripts/bullet.gd`, `scripts/projectiles/bullet_laser.gd`) override `_apply_visuals()` to attach glow, trails, or other polish. The base is a no-op (`func _apply_visuals() -> void: pass` at line 81–82), so a plain `BaseBullet` instance moves and hits without any visual frills. Example from `scripts/bullet.gd:22–28`:

```gdscript
func _apply_visuals() -> void:
	GlowShaderFx.apply_to_host(self)
	if guided:
		TrailFX.attach_trail(self, true)
```

This attaches a shader glow (see "GlowShaderFx" below) and optionally a trail.

### `base_missile.gd` — two-phase ordnance

`scripts/projectiles/base_missile.gd:1` is the base for any warhead that drifts, then ignites, then homes or accelerates. It extends `EnemyBase` (so it has health, can emit signals, has a sprite) but overrides the weapon pipeline:

- **Drift phase** (0 to `drift_time`): moves at `drift_speed` in the initial direction.
- **Ignite** (at `drift_time`): switches to `homing_accel` and starts steering/accelerating.
- **Fuse expiry** (at `fuse`): detonates with full explosion VFX.

Key exports:

| Export | Type | Default | Purpose |
|--------|------|---------|---------|
| `target_group` | String | "player" | "player" = enemy missile, "enemies" = player missile. Flips homing target + group membership. |
| `drift_time` / `drift_speed` | float | 0.25 / 80.0 | Initial free-fall phase before ignition. |
| `homing_accel` / `homing_max_speed` | float | 380 / 220 | Acceleration & speed once ignited. |
| `seeker_cone_deg` / `prefer_large` | float / bool | 25 / false | Only lock onto targets within this cone. Anti-ship: prefer largest in-cone target instead of nearest. |
| `dumb_fire` | bool | false | True = accelerate straight (rockets); False = home toward target. |
| `flame_trail` | bool | false | True = emit smoke trail from the exhaust marker (cosmetic). |
| `fuse` | float | 6.0 | Seconds. Auto-detonate at this time (not onscreen kill). |
| `damage_on_contact` | int | 1 | Damage to deal on hit. Single HP, so any bullet kills it. |

**One-shot lock (player missiles):** When `target_group == "enemies"` and `dumb_fire == false` (player seeking missile), the missile locks onto a single target in `_find_homing_target_in_cone()` and never re-acquires. If the target dies, it flies straight. This prevents the missile chasing phantoms across the screen. See `base_missile.gd:183–194` for the logic.

---

## Effects: Static VFX Helpers

Effects in this project follow a **static-helper pattern.** Rather than instancing a node, you call a static method on a helper class. The helper spawns VFX at the scene root (so it outlives the caller) and returns. No reference needed; the effect owns its lifecycle.

**Canonical helpers** — each is called as `ClassName.method(...)`:

### `hit_flash_fx.gd:19`

```gdscript
static func flash(target: CanvasItem, color: Color = FLASH_WHITE, duration: float = 0.12) -> void
```

Brief white (or colored) flash on a Sprite2D when hit. Used by:
- `base_bullet.gd:284` → white flash on enemy hit
- `player.gd` → white on hull hit, cyan on shield hit
- `mine_shielded.gd` → blue on shield hit

**Usage:** `HitFlashFx.flash(enemy_sprite, HitFlashFx.FLASH_WHITE, 0.12)`

The first call to `.flash()` lazily installs a `ShaderMaterial` (the `hit_flash.gdshader` at line 13). Concurrent flashes kill the previous tween so rapid fire stays bright instead of stuttering. Gated: if the sprite already has a non-flash shader (burn, etc.), flash gives way and skips.

### `explosion_fx.gd:11, :26`

```gdscript
static func play(world_pos: Vector2, scale: float = 1.0, with_light: bool = true) -> Node2D
static func burst(world_pos: Vector2, count: int = 1, jitter_radius: float = 10.0, stagger: float = 0.06) -> void
```

Fires an explosion scene at a position.

**Key point:** big enemies don't use a stretched 2× sprite — they call `.burst(count=3)` to spawn three simultaneous explosions with jitter and timing offsets. This reads as "many simultaneous blasts" and keeps physics/hitbox sizes honest. All blasts are at native 1× scale. See `base_missile.gd:466` for an example.

### `impact_fx.gd:37`

```gdscript
static func spawn(parent: Node, world_pos: Vector2, color: Color, kind: int = ImpactKind.SMOKE) -> void
```

Bullet-hit flash strip. Two modes:

- **ImpactKind.SMOKE** (0): small projectile impact. Colored flash (first frames) fading to gray.
- **ImpactKind.EXPLOSIVE** (1): warhead impact. Layered impact flash + full fiery explosion.

Called from `base_bullet.gd:313` when the bullet fizzles. Color is set by `impact_color` (usually cyan for player, magenta for enemies).

### `muzzle_fx.gd:38, :53, :99, :145`

```gdscript
static func play(world_pos: Vector2, host: Node = null) -> void
static func play_energy(world_pos: Vector2, host: Node = null) -> void
static func play_rotary_laser(world_pos: Vector2, host: Node = null) -> void
static func play_enemy(world_pos: Vector2, dir: Vector2, root: Node) -> void
```

Player firing muzzle flash + smoke trail + shell casing. Three flavors for the three player weapon types. Enemy fire gets its own simpler variant. The `host` parameter (optional) parents the flash under the player so it inherits the ship's transform (used by the `star_flash` beam windup).

### `enemy_engine_fx.gd:25`

```gdscript
static func attach(enemy: Node2D, tint: Color = FLAME_TINT, scale_mult: float = 1.0) -> Node2D
```

Attaches a flickering orange engine flame to an enemy's rear. Called from `_ready()` to add polish to flying enemies. The flame is a child sprite with z_index = -1 (drawn behind the body) and additive blending.

### `shield_sfx.gd:29, :36`

```gdscript
static func play_hit(parent: Node, world_pos = null) -> void
static func play_break(parent: Node, world_pos = null) -> void
```

Shield hit / break audio. Wired by `base_bullet.gd:277` when a bulwark-shielded enemy takes a hit.

### Other effects

- `death_dust.gd:55` → `static func play(...)` Spawn drifting debris on enemy death.
- `burn_fx.gd` → Apply a burning overlay shader on death (noted in CLAUDE.md; currently gate code).
- `damage_smoke_trail.gd` → Attached to the player when hull ≤ 50% (see Doc 04).
- `missile_smoke_trail.gd` → Smoke trail line behind missiles.
- `engine_torch.gd:83` → `static func attach_to_player(...)` Attach burning nozzle at the player's rear during high-damage states.
- `sfx.gd:27` → `static func play_one_shot(...)` Spawn an AudioStreamPlayer at a world position.

---

## GlowShaderFx: Shader-Based Additive Halos

`scripts/effects/glow_shader_fx.gd:1` is the **single code path for bright things** (projectiles now; engines / explosions / muzzle flashes later). It replaces the old `glow_fx.attach_glow()` radial halos.

### How it works

A fragment shader on a sprite can only draw *inside* the texture. To get an outer halo, a separate slightly-larger quad is positioned behind the host (`z_index = -1`) carrying the same texture + the `glow_halo.gdshader`. The shader softens the upscaled silhouette into a bloom without multi-tap blurring.

**Static methods:**

```gdscript
static func apply(host: CanvasItem, color_override: Color = Color(0, 0, 0, 0)) -> CanvasItem
```

Derives the glow color from the host's texture (the brightest, most-saturated non-white pixel), creates a `Sprite2D` halo quad, and attaches it as a sibling behind the host. If `color_override.a > 0`, that color is forced instead. Returns the glow node.

**Color derivation:** Computed once per texture on the CPU and cached by texture ID (line 49). The ShaderMaterial is then cached per glow color (line 51), so every bullet of the same color shares one material. Textures with no derivable color (pure white / greyscale) get NO glow — acceptable by design.

**Multi-frame sprite gotcha:** For animated bullets, the glow is **static** (the first frame's silhouette stays as the bullet animates). This is intentional — a 16×16 bullet is too small for per-frame glow ghosting to be imperceptible (see line 105–107). The tradeoff: the halo doesn't pulse with the animation, but it also doesn't ghost neighboring frames into the bloom.

**Usage:** From `scripts/bullet.gd:26`:
```gdscript
GlowShaderFx.apply_to_host(self)
```

`apply_to_host()` at line 157 is a convenience: find the bullet's Sprite2D child and apply glow to it.

---

## Shadows: Oblique drop-shadows on ships & large projectiles

`scripts/shadow_fx.gd:28` provides:

```gdscript
static func attach_shadow(
	host_sprite: Node,
	offset_world: Vector2 = DEFAULT_OFFSET_WORLD,
	opacity: float = DEFAULT_OPACITY,
	softness_px: float = DEFAULT_SOFTNESS_PX
) -> Node:
```

Attaches an oblique-shadow Sprite2D (using the `oblique_shadow.gdshader`) as a child of the host, offset down-right to fake a high sun. **Currently disabled** (line 12: `SHADOWS_ENABLED := false`) as of 2026-05-30; revisit in a dedicated pass.

**Shadow rule:** Oblique shadows apply only to **ships + LARGE projectiles** (missiles, bombs). Never small bullets — the shadow would be bigger than the projectile and read as clutter.

---

## Backdrop & Parallax Stack

The backdrop is a per-level layered environment built in `scripts/galaxy_backdrop.gd` and the `scripts/parallax/` folder. It's a **Parallax2D** coordinator with six CanvasLayer children:

1. **Deep sky** — a low-contrast tiled image, drifts slowest
2. **Starfield** — procedural twinkling stars (shader)
3. **Nebula layers** — colorful wisps (shader, multiple depths)
4. **Planet** — one PixelPlanets scene per level (weighted random pick)
5. **Asteroids** — 3–5 decorative asteroids with per-band drift rates
6. **Warp streaks** — hyperspace-ish vertical streaks (foreground, optional)
7. **Vignette** — darkened frame edge (CanvasLayer 10, highest z)

Each layer drifts downward at a different rate (parallax effect). The **planet** is the visual anchor — one per level, weighted to match the sector aesthetic.

### PixelPlanets pixel-parity setup (CRITICAL)

Every PixelPlanets scene (`Planets/*/...tscn`) placed into *any* scene must follow this exact order:

```gdscript
# Step 1: Set scale = size / 100.0 (PixelPlanets is authored at 100×100)
p.scale = Vector2(actual_size / 100.0, actual_size / 100.0)

# Step 2: add_child() FIRST — this fires _ready() and initializes ColorRect children
add_child(p)

# Step 3: THEN call _apply_pixel_parity() to reset ColorRect sizes
_apply_pixel_parity(p, actual_size)
```

**Why the order matters:** PixelPlanets resizes its ColorRect children via the node tree. If you call `_apply_pixel_parity()` *before* `add_child()`, the ColorRects don't exist yet, so the reset is a no-op. When `add_child()` fires `_ready()`, PixelPlanets re-initializes the ColorRects at the wrong size, silently mismatching shader cells. See `scripts/parallax/layer_planet.gd` for the canonical implementation and `docs/godot-patterns.md` → "PixelPlanets: `_apply_pixel_parity()` must be called AFTER `add_child()`" for the engine quirk details.

### Parallax backdrop architecture

The backdrop coordinator lives at `scripts/galaxy_backdrop.gd` and uses a `Parallax2D` node (from `addons/parallax2d/`) to drive per-layer scroll rates. Layer depth is controlled via CanvasLayer Z-depths (negative, so they render below gameplay). Material duplication and shader parameters are cached to avoid per-instance waste. See `docs/godot-patterns.md` for CanvasLayer transform limitations and material-sharing gotchas.

---

## Visual iteration loop (brief)

When you're developing a visual mechanic (a new weapon effect, enemy flame, explosion variation):

1. **Write a one-shot capture script** at `tools/capture_<mechanic>.gd` (reference `scripts/dev/wave_tester.gd` for the pattern).
2. **Create a `.ps1` wrapper** at `tools/capture_<mechanic>.ps1` (run the script, then feed output frames to ffmpeg).
3. **Post the GIF** to Discord in the dev channel (no PNG frames). Roman or the team reviews and comments.
4. **Don't read frame-by-frame** unless actively debugging a specific visual bug — that's slow and error-prone. The GIF review is the fast feedback loop.

See Doc 01 for the workflow philosophy.

---

## Walkthrough: Add a new projectile

This is end-to-end: extend a bullet, wire it into a scene, spawn it, verify.

### Step 1: Create a script (or reuse a variant)

If your bullet is **data-only** (different speed/damage/sprite, same straight-line behavior), the **BulletVariant Resource** system is the target design — see `docs/bullet_library_2026-05-24.md` for the spec (currently deferred, awaiting sprite assets). Today, you'll extend `base_bullet.gd` instead.

If your bullet has **bespoke behavior** (wobble, homing, split-on-death), extend `base_bullet.gd`:

```gdscript
# scripts/projectiles/bullet_mynew.gd
extends "res://scripts/projectiles/base_bullet.gd"

func _apply_visuals() -> void:
	# Attach glow, trails, or other polish here.
	GlowShaderFx.apply_to_host(self)
```

Keep it lean. Override `_apply_visuals()` for VFX attachment. If behavior is more complex (homing with evasion, multi-stage detonation), check if a variant hook (wobble_amplitude, homing_rate) covers it first.

### Step 2: Create a scene

Create `scenes/projectiles/bullet_mynew.tscn`:

1. Root node: `Area2D`, script = `res://scripts/projectiles/bullet_mynew.gd`
2. Add `Sprite2D` child, texture = your bullet sprite
3. Add `CollisionShape2D` child, shape = CircleShape2D or RectangleShape2D (size matches your sprite)
4. Export properties in the inspector (speed, damage, etc.)

**Scene template reference:** `scenes/projectiles/bullet.tscn:9–27` (lines 9–27) shows the minimal structure (Bullet root, Sprite2D, CollisionShape2D × 2, VisibleOnScreenNotifier2D, signal connection). Copy that structure.

### Step 3: Spawn from code

**Critical:** spawn as a child of `get_tree().root`, not the shooter.

```gdscript
# From anywhere (enemy, player, weapon):
const BulletScene = preload("res://scenes/projectiles/bullet_mynew.tscn")
var b = BulletScene.instantiate()
b.start(muzzle_world_pos, fire_direction)
get_tree().root.add_child(b)
```

Or if using a variant:

```gdscript
var b = BulletScene.instantiate()
b.variant = load("res://resources/data/bullets/heavy_slug.tres")
b.start(muzzle_world_pos, fire_direction)
get_tree().root.add_child(b)
```

### Step 4: Commit .uid sidecar files

Godot auto-generates `.uid` files (like `bullet_mynew.tscn.uid`). **Commit them.** Never hand-edit `.uid` files. See Doc 06.

### Step 5: Verify headless

```powershell
godot --path . --headless --quit-after 2
```

If you get parse errors, the scene won't load. Fix them and re-run.

Then boot the actual scene:

```powershell
godot --path . --scene scenes/main.tscn --headless --quit-after 5
```

If the bullet spawns, moves, hits, and fizzles without exceptions, you're good.

---

## Adding an effect helper (brief)

If you need a new static effect (a new muzzle flash style, a shield-break animation, etc.):

1. **Create a new script** in `scripts/effects/` with static methods.
2. **Call it from the event** where it should fire (on enemy death, on shield break, etc.).
3. **Spawn the effect at `get_tree().root`** so it outlives the caller.

Example stub:

```gdscript
# scripts/effects/shield_break_fx.gd
extends Node

static func play(world_pos: Vector2, shield_type: int = 0) -> void:
	# Instantiate, position, and parent at the root.
	var explosion = preload("res://scenes/effects/explosion.tscn").instantiate()
	explosion.global_position = world_pos
	Engine.get_main_loop().root.add_child(explosion)
```

Call it:

```gdscript
ShieldBreakFx.play(self.global_position)
```

No instance creation, no reference tracking. The effect owns its own lifecycle and cleans up when done.

---

## Cross-links

- **Who fires these bullets?** Docs 03 (enemy patterns) and 04 (player weapons).
- **Development workflow & tuner philosophy?** Doc 01 → "The visual iteration loop."
- **Godot engine quirks** (CanvasLayer transforms, material duplication, multi-frame sprite ghosting)? → `docs/godot-patterns.md`.
- **Rules & traps** (hitbox philosophy, explosion scale, no silent fallbacks) → Doc 06.
- **Bullet variant catalog** → `docs/bullet_library_2026-05-24.md`.
