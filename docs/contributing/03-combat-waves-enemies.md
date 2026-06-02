# 03 · Combat, Waves & Enemies

This doc explains the combat loop, how waves become enemies on the playfield, and the enemy architecture so you can add or modify an enemy with confidence.

**Related docs you should know exist:**
- **Doc 02 (Architecture)** — scene flow, autoloads, playfield bounds, when to import `Playfield`
- **Doc 04 (Player, Parts & Economy)** — damage model, bounty economy, Part system
- **Doc 05 (Projectiles, Effects & Visuals)** — bullet behavior, VFX, muzzle flashes, shadows
- **Doc 06 (Conventions & Gotchas)** — edge cases you'll trip over; keep it open

---

## The Combat Loop, End to End

Every combat encounter follows this chain. Knowing it helps you debug and understand where to hook your own changes.

**1. Main picks a level → director spawns enemies → waves clear → outro fires.**

```
main.gd new_game()
    ↓ (builds LevelData)
    ├─ WaveGen.build(sector_depth, level_index_in_sector, is_boss)
    │  [production wave generator]
    │
    ├─ WaveGeneratorV2.build_combat(...)
    │  [dev Wave Tester tool — when tuning]
    │
    └─ Levels.build_minefield_level() / build_asteroid_field_level()
       [hazard nodes — minefields, asteroids]

    ↓ (level is a LevelData resource)
    
wave_director.start_level(_current_level)
    ↓ (iterates waves)
    
For each wave in level.waves:
  emit wave_started(idx, total, silent, announce_text)
  [WaveSpec is a Resource with count, formation, spawn_interval, etc.]
  
  For each enemy in wave.count:
    _spawn_enemy(wave, index)
      → instantiate wave.enemy_scene
      → apply per-wave overrides (movement, shoot_pattern, health, bounty)
      → set position (formation-based: left-to-right, random, tandem pairs, etc.)
      → add_child() + add_to_group("enemies")
      → emit enemy_spawned(scene_path, bounty_value)
      → enemy.start(pos) or enemy.spawn(pos)
    
    (loop continues at wave.spawn_interval)
  
  When all enemies spawned:
    _wait_for_clear_then_advance()
    ↓ (polls "enemies" group)
    ↓ (until empty AND POST_CLEAR_GRACE passes)
    
    emit level_cleared

main.gd _on_level_cleared()
    → _run_outro()
      → 0.8s grace period (bullets settle)
      → disable player collision
      → fly player up off-screen
      → fade to black
      → show ClearedSummaryScene
```

**Key signals from the director** (`scripts/levels/director.gd`):

- `wave_started(wave_index: int, wave_count: int, silent: bool, announce_text: String)`
  Fired once per wave, before spawning enemies. The HUD listens to update the wave counter.

- `enemy_spawned(scene_path: String, bounty_value: int)`
  Fired when each enemy instantiates. Main.gd uses this to track kill stats and player codex.

- `enemy_died(value: int, scene_path: String)`
  Fired when an enemy emits its `died` signal. Main.gd adds the bounty and applies modifiers.

- `level_cleared`
  Fired when all waves have spawned AND the "enemies" group is empty (and hazards are gone).
  Main.gd responds by running the outro.

**Three paths build levels:**

1. **`WaveGen.build(sector_depth, level_index, is_boss)`** — production.
   Dynamic generator that composes waves from the enemy roster, weighted by rarity and sector depth. Called when entering a standard combat node or a boss arena.

2. **Manual wave authoring via Wave Editor** — development.
   The `wave_editor.gd` dev tool (Dev Menu → Wave Editor) lets you author individual waves by hand, test them in-game, and save to `resources/waves/`. Never ships to players.

3. **`Levels.build_minefield_level()` / `build_asteroid_field_level()`** — hazards.
   Hardcoded hazard nodes (minefields, asteroids). Not spawned by the wave generator; called directly when the sector map rolls a hazard node.

---

## How a Wave Becomes Enemies

The flow is: **Roster** → **Wave Spec** → **Director spawns** → **Enemies live on playfield**.

### 1. Enemy Roster: the Spawn Pool

`scripts/levels/enemy_roster.gd` is a static lookup table. Every combat enemy is registered there with metadata so the wave generator knows what it can pick from, when it's available, and how to scale it.

**Example entry:**
```gdscript
{
    "scene": "res://scenes/enemies/enemy_dart.tscn",
    "tier": Tier.COMMON,
    "size": "small",
    "movement": "fast_straight",
    "shoot": null,  # melee/no-fire enemies have null shoot pattern
    "base_count": 8,           # default enemies per wave at entry level
    "hp_override": 1,
    "bounty_override": 5,
    "unlock_sector": 0,        # available from sector 0 onward
    "unlock_depth": 0,         # available from depth 0 onward
    "weight": 1.4,             # relative spawn frequency (chaff boosted)
    "chaff": true,             # counts as cannon fodder (affects mixing)
}
```

**Gating fields:**
- `unlock_sector` — this enemy only appears in sectors >= this value. Dart (0) is always available; Strafe's (1) to avoid overwhelming the first combat.
- `unlock_depth` — within an unlocked sector, this enemy only spawns at combat depth >= this. Lets you gate powerful enemies to the 2nd+ node of a sector.
- `weight` — relative spawn frequency. Chaff gets boosted (1.4) to increase pool density at shallow depths.

**When does an entry become eligible?**
Call `Roster.entries_eligible(sector_idx, sector_depth)` — it returns all entries where `unlock_sector <= sector_idx AND unlock_depth <= sector_depth`.

### 2. Wave Spec: the Composition

A `WaveSpec` (defined in `scripts/levels/wave_def.gd`) describes one wave of enemies: which scene to spawn, how many, at what formation, what overrides apply.

```gdscript
@export var enemy_scene: PackedScene          # the scene to spawn
@export var count: int = 6                    # how many instances
@export var spawn_interval: float = 0.35      # spawn cadence (seconds between)
@export var spawn_delay: float = 0.5          # delay before first enemy
@export var formation: int = TOP_LEFT_TO_RIGHT
@export var formation_padding: float = 32.0   # X-axis margin from playfield edges

# Per-wave overrides (applied after instantiate, before start())
@export var movement_override: Resource = null      # swap the movement pattern
@export var shoot_pattern_override: Resource = null # swap the shoot pattern
@export var fire_interval_min: float = -1.0        # override fire cadence
@export var fire_interval_max: float = -1.0
@export var max_health: int = -1                    # override HP
@export var health_bonus: int = 0                   # additive HP bonus
@export var bounty_value: int = -1                  # override bounty payout

@export var silent: bool = false                    # if true, no WAVE banner
@export var announce_text: String = ""              # custom banner text
```

**How waves are composed:**

`WaveGen.build()` starts with an empty `LevelData` and fills it with `WaveSpec`s based on sector depth and the current combat index. The logic is conceptual: **first wave = 1 type, 2 waves; deepening combats add a third type or more waves; rare rolls mix two types together (intermingling).**

Overrides let the generator tweak individual instances — e.g., "Darts this wave have +1 HP" or "Firecores this wave fire 20% faster."

### 3. Director Spawns

`WaveDirector._spawn_enemy(wave, index)` (director.gd:110) walks the recipe:

1. **Instantiate** the scene from `wave.enemy_scene.instantiate()`
2. **Apply overrides** — movement/shoot/health/bounty from the wave
3. **Compute spawn X** based on the wave's formation (left-to-right, random, tandem pairs, alternating sides)
4. **Add to world** as a child of the director's parent and add to the "enemies" group
5. **Call `start(pos)`** — enemy initializes its pattern and timer
6. **Emit `enemy_spawned`** — main.gd hooks this to track kill stats

---

## Enemy Architecture

All enemies in the "enemies" group descend from a two-tier hierarchy:

### Tier 1: `EnemyBase` — Shared Fundamentals

`scripts/enemies/enemy_base.gd` (class_name `EnemyBase`) — the Area2D that every enemy extends or composes.

**Shared responsibilities:**
- Health system: `max_health`, `health`, `take_hit(damage) → bool` (returns true if killed)
- `explode()` — death VFX (debris, burn, explosion)
- `died` signal — emitted on death with bounty value
- Auto-rotate the sprite to face velocity direction (driven by `auto_rotate` bool)
- Engine flame + parallax shadow + damage overlay shader (auto-applied if `auto_rotate=true`)
- Off-screen cleanup (mode: CYCLE_BOTTOM / FREE_ANY_EDGE / FREE_OPPOSITE_SIDE / NONE)
- Muzzle marker system — resolves Marker2D children named `Muzzle*` / `cannon_*` for bullet origins + flashes
- Shield rings (decorative visual; does NOT gate health — shield is a CHARGE pool for the player)

**Key exports (set in .tscn):**
```gdscript
@export var max_health: int = 1
@export var bounty_value: int = 5
@export var auto_rotate: bool = true           # face velocity direction
@export var is_hazard: bool = false            # mines/asteroids skip wave clear gates
@export var offscreen_mode: int = CYCLE_BOTTOM # behavior when off-screen
```

**Contract for bullets:**
Bullets call `area.take_hit(damage)` on hit. Returns true if the enemy dies. The bullet uses this to know whether to trigger death VFX on its end.

### Tier 2: `EnemyCore` — Pattern-Driven Ships

`scripts/enemy_core.gd` (extends `EnemyBase`) — adds two Resource slots:

```gdscript
@export var movement: Resource = null      # a movement_pattern.gd subclass
@export var shoot_pattern: Resource = null # a shoot_pattern.gd subclass
@export var fire_interval_min: float = 1.2
@export var fire_interval_max: float = 2.5
```

**What they do:**

- **`movement`** — a movement_pattern.gd Resource. The pattern owns how the enemy navigates: descend straight, drift, loiter, weave, dive, etc.
  - Call `movement.on_start(self)` on spawn
  - Each frame, call `movement.compute_step(self, delta)` → returns the pixel displacement for this frame
  - Enemy_core applies it: `position += step`, then clamps to sides, checks off-screen, applies rotation

- **`shoot_pattern`** — a shoot_pattern.gd Resource. The pattern owns how the enemy fires: single shot, spread, burst, aimed, etc.
  - The director starts a `ShootTimer` that calls `_on_shoot_timer_timeout()`
  - Timeout fires `shoot_pattern.fire(self)` → pattern spawns bullets
  - Pattern owns direction logic (straight down, angled, aimed at player, etc.)

**Off-screen recycling** — `CYCLE_BOTTOM` mode (the default):
When the enemy drifts off the bottom, instead of freeing, it tweens back up through the parallax layers and re-enters from the top. A recycling enemy reports `is_recycling() = true` so the wave-advance gate ignores it (other enemies can clear while recyclers fly back).

**Sector speed scaling** — `_apply_sector_speed_scale()` (enemy_core.gd:90):
When an enemy spawns, its movement pattern is duplicated and speed-scaled by +5% per cleared sector, capped at 2×. This makes later sectors feel faster without changing the wave generator's composition logic.

### Tier 2b: Bespoke Enemies

Some enemies extend `EnemyBase` directly, not `enemy_core`. They own complex multi-phase behavior that can't be expressed as a single movement + shoot pair:

- **Burner** — two ships beam-linked, descend together, die together
- **Strafer** — three-phase: home in, fire 6-round burst, veer off
- **Firecore Drone** — rings of orbiting projectiles that auto-fire
- **Gunship / Frigate / Beamer / Bomber** — arrive → settle → sweep/hold while firing a signature weapon (rockets, perpendicular broadside, swept beam, rear tail-turret)

**When to write bespoke vs. pattern:** See the convention below.

#### The bespoke-enemy recipe

A bespoke enemy self-drives and self-fires, so the roster entry hands it **no** movement/shoot Resource. The director applies overrides guarded by `if "<prop>" in enemy` (see `director.gd`), and `EnemyBase` has **no** `movement`/`shoot_pattern` properties — so those overrides are silently skipped, while `max_health`/`bounty_value` (which `EnemyBase` *does* have) still apply. That gives a clean division: roster data sets the **stats**, your script owns the **behavior**.

1. **Roster:** set `"movement": null, "shoot": null`. Drive stats with `"hp_override"` / `"bounty_override"` (and `"no_scale": true` if a formation needs an exact count — e.g. a fixed wing). `make_movement(null)` returns a throwaway `StraightDown` the director discards, so `null` is safe.
2. **Stats:** set `max_health`/`bounty_value` in `_ready()` **before** `super._ready()` (see the override-pipeline section below). The roster's `hp_override` then overwrites them on spawn — keep the two roughly in sync so manual placement (dev menu) still behaves.
3. **Entry points** — the director calls these, in order, right after `add_child`:
   - `on_spawned_in_wave(index, count)` *(optional)* — derive a per-instance role from spawn order (the gunship picks single/duo/trio this way).
   - `start(pos)` — override it to reposition. Top-spawned enemies keep `pos`; side-entry enemies (frigate cross, minelayer) ignore it and place themselves just outside the playfield band (`Playfield.X_MIN - N` / `X_MAX + N`).
4. **Locomotion:** move `position`/`global_position` yourself in `_process(delta)`, then call `super._process(delta)` **last**. The base `_process` only does bookkeeping — auto-rotation (from your position delta) and offscreen cleanup — so the gunship/frigate model is "move, then `super`." Set `offscreen_mode` in `_ready()` to match how the enemy leaves (`FREE_ANY_EDGE`, `FREE_OPPOSITE_SIDE`, or `NONE` to stay until killed).

> **`display_scale` is NOT a transform.** It only scales explosion/debris VFX in `EnemyBase`, and roster `size` only drives hp/shield/bounty/speed — neither resizes the sprite. Enemies render at the scene's native scale; size a sprite by drawing it, not by scaling the node. See Doc 06.

---

## Movement & Shoot Patterns: Resources

Both are preloaded from `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/`.

### Movement Patterns

Base: `scripts/enemies/movement_pattern.gd` (extends Resource).

**Contract:**
```gdscript
func on_start(_enemy) -> void:
    # Called once when the enemy spawns. Reset all state. Patterns are
    # duplicate()'d per enemy so siblings don't share state, but
    # parallax-recycled enemies call this again after each fly-back.
    pass

func compute_step(_enemy, _delta: float) -> Vector2:
    # Return the position delta (pixels) for this frame. NEVER mutate
    # enemy.position directly — the caller applies the step.
    # This shape lets position-based patterns (sin-wave) coexist with
    # velocity-based ones.
    return Vector2(dx, dy)
```

**Examples from the repo:**

- **`straight_down.gd`** — constant vertical descent + optional horizontal drift
  ```gdscript
  @export var speed: float = 100.0       # px/s downward
  @export var drift_x: float = 0.0       # px/s sideways
  # compute_step returns (drift_x, speed) * delta
  ```

- **`loiter.gd`** — hover at spawn, sway side-to-side
- **`advance_retreat.gd`** — descend, pull back up, repeat
- **`s_curve.gd`** — sideways S-shaped arc while descending
- **`beeline_player.gd`** — track toward player position

### Shoot Patterns

Base: `scripts/enemies/shoot_patterns/shoot_pattern.gd` (extends Resource).

**Contract:**
```gdscript
func fire(_enemy) -> void:
    # Called when the enemy's ShootTimer times out (or when a phase event
    # fires if fire_on_phase is set). Spawn bullets by calling
    # _spawn_bullet(enemy, direction, bullet_variant).
    pass

@export var bullet_variant: BulletVariant = null
# Optional variant to override bullet speed/damage/hitbox at spawn.
```

**Examples:**

- **`single_shot.gd`** — one bullet straight down (or angled/aimed toward center)
- **`spread_shot.gd`** — 3–5 bullets in a fan
- **`burst_shot.gd`** — rapid 3–4 rounds with brief cooldown between
- **`aimed_fire.gd`** — sniper-style single shot aimed at the player

**Muzzle markers** — defined in the enemy scene as Marker2D children named `Muzzle*` or `cannon_*`. When a shoot pattern calls `_spawn_bullet()` and the enemy has muzzles, the bullet spawns from the next muzzle (cycling index alternates for two-muzzle enemies like the Weaver). A muzzle flash plays at each muzzle.

---

## Core Convention: Prefer Patterns Over Bespoke Scripts

**PATTERN-DRIVEN (most common):**
- Extend `enemy_core.gd`
- Declare a `movement` and `shoot_pattern` Resource
- The base class owns all the timing, off-screen logic, auto-rotate, and health system
- Example: Firecore (movement="firecore_straight", shoot="single_diagonal")

**BESPOKE (rare):**
- Extend `enemy_base.gd` directly
- Own multi-phase locomotion or weapon behavior that a single movement/shoot pair can't express
- Example: Burner (two ships, one beam, synchronized dive)

**When to go bespoke:** You need continuous state across multiple phases (e.g., "I'm in phase 1, tracking X, and the shoot pattern needs to fire 6 rounds then switch modes"). A pattern is a stateless recipe; if your enemy is a state machine, extend `enemy_base` directly.

---

## Key Rules

These live in CLAUDE.md but are so important they're restated here. See Doc 06 for the full trap compendium.

### Rule: Auto-rotate Defaults to True

Every enemy starts with `@export auto_rotate: bool = true` in enemy_base.gd. This makes the sprite auto-rotate to face the velocity direction.

**Do NOT disable it because the sprite art "should face down."** The base class handles that — legacy .tscn files that have Sprite2D.flip_v = true get corrected in `_ready()` (enemy_base.gd:137).

Mines, asteroids, and turrets disable it in their `_ready()`, and that's correct — they don't have a "front."

### Rule: Enemy Hitbox = Full Sprite Size

Set the CollisionShape2D to match the sprite bounds exactly. No shrinking for "forgiveness" (the player ship gets hitbox forgiveness, enemies don't).

### Rule: Import `Playfield` for Bounds

Patterns that move enemies side-to-side MUST import `scripts/playfield.gd` and use `Playfield.X_MIN`, `X_MAX`, `CENTER` for clamping. Never `get_viewport_rect()` (returns full 480 width; the playfield is only 216 wide in the center).

---

## Walkthrough: Add a New Enemy

This is the real end-to-end recipe. We'll add a hypothetical "Swooper" — a small ship that homes at the player and fires bursts.

### Step 1: Pick Movement & Shoot Patterns

Browse `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/` for existing patterns you can use.

For Swooper:
- **Movement:** Use `beeline_player.gd` — it homes toward the player. (If none fit, you might write a new pattern, but exhaust existing ones first.)
- **Shoot:** Use `burst_shot.gd` — fires 3 rounds with a gap. (Already exists; no custom logic needed.)

If you needed custom movement (e.g., "spiral while homing"), you'd write a new `spiral_beeline.gd` extending `movement_pattern.gd`. Same for shooting.

### Step 2: Create the Scene

Root: **Area2D** (class: `EnemyCore`, scripts: `scripts/enemy_core.gd`), groups: `["enemies"]`, name: `Enemy`

```
Enemy (Area2D, EnemyCore)
├─ Sprite2D (texture: your_swooper_art.png)
├─ CollisionShape2D (RectangleShape2D, size matches sprite bounds)
├─ MoveTimer (Timer, one_shot=true)
├─ ShootTimer (Timer, one_shot=true)
├─ EnemyShoot (AudioStreamPlayer2D, stream: SFX_shot.wav)
└─ EnemyDie (AudioStreamPlayer2D, stream: SFX_die.wav)
```

**(See `scenes/enemies/enemy_dart.tscn` for a complete example.)**

### Step 3: Configure the Root

In the Inspector, set:

- **Script:** `res://scripts/enemy_core.gd`
- **Max Health:** `3` (Swooper has more HP than Dart's 1)
- **Bounty Value:** `12`
- **Movement:** Drag `scripts/enemies/patterns/beeline_player.gd` into the slot, or create an instance:
  ```gdscript
  const BelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
  # In the scene, right-click the Movement field → "Make Unique (Sub-Resources)"
  # Then set Speed=150.0, TurnSpeed=180.0 (tune to taste)
  ```
- **Shoot Pattern:** Drag `scripts/enemies/shoot_patterns/burst_shot.gd`, configure:
  - **Bullet Scene:** `res://scenes/projectiles/enemy_bullet.tscn`
  - **Bullet Variant:** (leave null or pick a variant if you want to tweak bullet speed/damage)
  - **Fire Interval Min:** 1.0
  - **Fire Interval Max:** 2.0

### Step 4: Register in the Roster

Edit `scripts/levels/enemy_roster.gd`, add to ENTRIES:

```gdscript
{
    "scene": "res://scenes/enemies/enemy_swooper.tscn",
    "tier": Tier.UNCOMMON,           # it has 3 HP and homes, so uncommon
    "size": "small",
    "movement": "beeline",           # just for documentation; the scene owns it
    "shoot": "burst",
    "base_count": 4,                 # 4 swoopers per wave at entry depth
    "unlock_sector": 1,              # sector 1+, not first combat
    "unlock_depth": 1,               # depth 1+
    "weight": 0.8,                   # slightly rarer than chaff
},
```

**Why these fields matter:**
- `tier` governs bounty scaling via `RARITY_BOUNTY_MULT` (common×1, uncommon×2, rare×4)
- `unlock_sector` / `unlock_depth` control when `Roster.entries_eligible()` includes this entry
- `weight` affects the random pick probability — higher = more common

### Step 5: Save and Commit

1. Save the `.tscn` — Godot auto-generates a `.uid` sidecar
2. **Commit the `.uid` file** along with the `.tscn`
   ```bash
   git add scenes/enemies/enemy_swooper.tscn
   git add scenes/enemies/enemy_swooper.tscn.uid
   git commit -m "enemies: add Swooper (homing burst fighter)"
   ```

### Step 6: Verify

**Headless boot:**
```bash
godot --path . --headless --quit-after 2
```

This truly compiles all scripts (parse_check false-passes compile errors). If the boot succeeds, your scene is valid.

**In-game:**
- Enter a Wave Tester session and manually spawn a Swooper to watch it move and fire
- Or load the enemy in a custom test level and verify it homes and fires bursts as expected

---

## Enemy Stats & the Director's Override Pipeline

The director applies per-wave overrides in this order:

1. **Enemy scene defaults** — whatever `max_health`/`bounty_value` are set in the `.tscn`
2. **Wave overrides** — `WaveSpec.max_health`, `bounty_value`, `movement_override`, `shoot_pattern_override`
3. **Sector modifiers** — if Run has `sector_modifiers` (e.g., "shielded" or "armored"), these apply last

Example: A Dart (1 HP by default) in a wave with `max_health=2` will have 2 HP. If the sector is "shielded," it gains a shield on top.

**Setting stats correctly (bespoke enemies):**

In bespoke `.gd` files (extending `EnemyBase`), set stats in `_ready()` **BEFORE** calling `super._ready()`:

```gdscript
func _ready() -> void:
    max_health = 3
    bounty_value = 20
    super._ready()  # CRITICAL: after setting stats
```

If you set them AFTER `super._ready()`, the base class has already copied `max_health` into `health` — your override becomes stale.

---

## Tips & Common Patterns

**Parallax recycling:**
Pattern-driven enemies default to `offscreen_mode = CYCLE_BOTTOM`. When they drift off the bottom, they tween back up and re-enter from the top, refreshing their health. This is visual — the same enemy instance cycles. Call `is_recycling()` to check if an enemy is mid-fly-back.

**Sector-based difficulty scaling:**
Enemy_core's `_apply_sector_speed_scale()` automatically boosts pattern speeds (+5% per sector, capped at 2×). No per-enemy changes needed.

**Wave intermingling:**
The generator sometimes mixes two enemy types in a single wave (higher probability in deeper combats). This gives variety without bumping difficulty aggressively. See `WaveGen.WAVE_INTERMINGLE_PROBS`.

**Fire on phase:**
Some patterns emit `phase_entered(phase_name)` signals (e.g., Hover's "hold" phase). Set `fire_on_phase = "hold"` on the enemy so it fires *only* when the phase enters, not on a timer. Ensures shots are thematically synchronized with the movement.

---

## Cross-References

- **Bullets & muzzle flashes** — Doc 05
- **Bounty payout & economy** — Doc 04
- **Player bounds & coordinate space** — Doc 02
- **Full convention & trap list** — Doc 06
- **Boss-specific (health before super._ready)** — boss_base.gd comments, boss.gd
