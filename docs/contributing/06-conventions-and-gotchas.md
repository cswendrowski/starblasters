# 06 · Conventions & Gotchas

**Keep this page open while you code.** It's a scannable checklist of the traps that have bitten the project before. For deep dives, see the authoritative sources: [`CLAUDE.md`](/CLAUDE.md) (house rules), [`docs/godot-patterns.md`](../godot-patterns.md) (engine quirks), and the walkthroughs in Docs 03–05.

---

## GDScript & Engine Traps

### `:=` on a Variant value is a HARD COMPILE ERROR

**The rule:** Never use `:= value` when the RHS type is unresolvable. Use `var x = value` (untyped, benign warning) or add an explicit type: `var x: Type = value`.

**Why:** Godot 4.6+ cannot infer types from function calls with no return annotation, untyped variables, or Godot autoload helpers like `get_node_or_null()`. The compiler fails with `Cannot infer the type of X because the value doesn't have a set type.` **`parse_check` FALSE-PASSES this error** — it only loads scenes, not recompiling scripts. To verify GDScript actually compiles, boot headless: `godot --path . --headless res://scenes/<scene>.tscn --quit-after 60` and grep output for `SCRIPT ERROR|Parse Error|Cannot infer|Failed to load`.

**Source:** [`docs/godot-patterns.md` → `:=` vs `=` warning`](../godot-patterns.md#gdscript--vs--for-type-inference)

---

### Boss and enemy stats set BEFORE `super._ready()`

**The rule:** If a `_ready()` method sets `hull`, `max_hull`, `max_shield`, or similar stats, assign them **before** calling `super._ready()`. The base class reads these values during its `_ready()` and initializes UI accordingly.

**Why:** Setting stats after `super._ready()` via a `<= 0 ? default` pattern caused a 1-HP bug where bosses died on any hit.

**Source:** [`CLAUDE.md` → Bosses](../CLAUDE.md#bosses-scriptsbossgd-boss_reavergd-boss_sentinelgd), [`docs/godot-patterns.md` → Boss stats](../godot-patterns.md#boss-stats-must-be-set-before-super_ready)

---

### `$Sprite2D` child node name is load-bearing

**The rule:** Enemy sprites must be named exactly `Sprite2D` (not `sprite`, `Sprite`, `SpriteNode`, etc.). The base class hardcodes this name.

**Why:** `enemy_base.gd` looks up `$Sprite2D` by name to attach the auto-rotate system, damage overlay shader, hit-flash, and burn effects.

**Source:** [`scripts/enemies/enemy_base.gd:100–126`](../../scripts/enemies/enemy_base.gd)

---

### CanvasLayer transforms don't inherit from parents

**The rule:** A `CanvasLayer` node ignores its parent's scale, rotation, and position — it always renders in viewport-absolute coordinates.

**Why:** This is a Godot design choice; CanvasLayers exist outside the normal 2D hierarchy.

**Fix:** To scale a backdrop with CanvasLayer children, change `Window.content_scale_size` or use a `SubViewport` inside a scaled parent.

**Source:** [`docs/godot-patterns.md` → CanvasLayer transform`](../godot-patterns.md#canvaslayer-does-not-inherit-parent-transforms)

---

### Material duplication before per-instance shader params

**The rule:** If a `.tscn` defines an inline `ShaderMaterial` without `resource_local_to_scene = true`, all instances of that scene share ONE material. Calling `material.set_shader_parameter(...)` writes to the shared copy — last-write-wins.

**Why:** You seed each instance differently (`set_seed(randi())` per asteroid) but they render identically because the material isn't duplicated.

**Fix:** Before setting any per-instance shader params, duplicate: `mat = mat.duplicate()`.

**Source:** [`docs/godot-patterns.md` → Material duplication`](../godot-patterns.md#duplicate-materials-before-setting-per-instance-shader-params)

---

### `_apply_pixel_parity()` must be called AFTER `add_child()`

**The rule:** When placing a PixelPlanets scene, call `add_child(p)` first (to fire `_ready()` and initialize ColorRect children), then `_apply_pixel_parity(p, size)`.

**Why:** The parity system resizes ColorRect children by accessing them in the node tree. If `_ready()` hasn't fired yet, the children don't exist and the reset is a no-op — they re-init at the wrong size when `add_child()` finally fires.

**Source:** [`docs/godot-patterns.md` → PixelPlanets order`](../godot-patterns.md#pixelplanets-_apply_pixel_parity-must-be-called-after-add_child), [`CLAUDE.md` → PixelPlanets placement`](../CLAUDE.md#conventions)

---

## Project Conventions

### Gameplay bounds from `Playfield`, never `get_viewport_rect()`

**The rule:** Import `scripts/systems/playfield.gd` and use `Playfield.X_MIN`, `Playfield.X_MAX`, `Playfield.CENTER`, or `Playfield.clamp_pos()` for gameplay bounds. Never call `get_viewport_rect()` for gameplay — it returns the full 480px width.

**Why:** The internal viewport is 480×270, but gameplay is constrained to a 216px-wide playfield band (X 132–348) with side gutters for HUD. Using the viewport rect lets entities drift into the glass panels.

**Source:** [`CLAUDE.md` → Project section`](../CLAUDE.md#project), [Doc 02 → Coordinate space](02-architecture.md#the-playfield-coordinate-space)

---

### Projectiles parent to `get_tree().root`, never the shooter

**The rule:** When spawning a bullet or missile, set its parent to the scene root: `get_tree().root.add_child(bullet)`. Never parent it to the enemy or player.

**Why:** The shooter `queue_free`s when it dies. If the projectile is a child, it gets freed too and disappears mid-air.

**Source:** [`CLAUDE.md` → Projectiles`](../CLAUDE.md#projectiles-scriptsprojectiles), [`scripts/enemies/shoot_patterns/shoot_pattern.gd:42`](../../scripts/enemies/shoot_patterns/shoot_pattern.gd)

---

### Hitbox sizing: enemies full sprite, player forgiven

**The rule:** Enemy collision shapes = full sprite bounding box. Player collision = sprite minus 2–4 px (narrower for forgiveness). Difficulty is tuned via HP, damage, and spawn rate — never by hitbox size.

**Why:** Consistent hitbox expectations prevent cheap-feeling deaths and make frame-perfect maneuvers fair.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions)

---

### Shadows only on ships and large projectiles, not small bullets

**The rule:** Oblique ground shadows (via `ParallaxShadow.attach()`) appear on the player, enemies, and large projectiles (missiles, bombs). Small bullets get no shadow.

**Why:** Shadows at this scale (480×270 viewport) visually ground large entities. Small bullets create visual clutter without reading clearly.

**Source:** User convention (enforced in practice — no shadows attached in `scripts/projectiles/base_bullet.gd`)

---

### `auto_rotate = true` is the default for enemies

**The rule:** Set `auto_rotate = true` on every enemy by default. Disable it only for hazards that don't have a "front" — mines, asteroids, turrets.

**Why:** Auto-rotate makes pattern-driven ships bank and feel responsive. Don't disable it because a sprite "points down" — the base class handles that.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions), [`scripts/enemies/enemy_base.gd:81`](../../scripts/enemies/enemy_base.gd)

---

### Explosions: 1× scale, burst counts, debris drifts frame-0

**The rule:**
- Explosion sprite scale is always **1×** (native size).
- Big enemies get **more blasts** via `.burst()`, not stretched sprites.
- Debris piece scale is fixed at **1×**; only the count scales with enemy size.
- Debris drifts downward **starting from frame 0** — never freeze-then-fall.

**Why:** Consistent visual language. Stretching looks cheap; layered smaller explosions read as more powerful.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions), [`scripts/enemies/enemy_base.gd:8–16`](../../scripts/enemies/enemy_base.gd)

---

### Commit `.uid` sidecar files, never hand-edit them

**The rule:** When you add a `.gd` or `.tscn`, Godot generates a `.uid` file (e.g., `my_script.gd.uid`). Commit it. Never hand-edit `.uid` files.

**Why:** UIDs are Godot's internal asset ID system. Hand-editing breaks cross-references.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions)

---

### `default_texture_filter = 0` (nearest) is intentional

**The rule:** The project.godot setting `default_texture_filter = 0` (nearest-neighbor) is intentional for pixel-art upscaling.

**Why:** Pixel art rendered with bilinear filtering becomes blurry at 4× scale.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions)

---

### Sprites render at native 1× — never scale them up

**The rule:** All enemy, player, and projectile sprites are shown at their **native 1× scale**. Don't add a node `scale` (or any upscaling) to make a small sprite "read bigger" — if it needs to be bigger, that's an art change. Some sprites are intentionally **long/non-square** (e.g. 32×64, 16×32); that aspect ratio is deliberate, not a mistake to "fix."

**Why:** The art is hand-drawn at the exact resolution it displays at; combined with nearest-neighbor filtering, 1× keeps it crisp. Upscaling reintroduces the blur/chunkiness the pixel art was tuned to avoid. Note `display_scale` on `enemy_base` is only a VFX/explosion-count hint — it is **not** a node transform and does not resize the sprite (Doc 03 → bespoke-enemy recipe).

**How:** Leave node `scale = (1,1)`; size the collision shape to the sprite's native pixel dimensions (long sprites get long hitboxes).

---

### New Part pattern (extend Part → slot_type → apply + unapply)

**The rule:** New Parts extend `Part`, set `slot_type` in `_init`, override `apply(ship)` (additive + record delta) and `unapply(ship)` (reverse), and register in `PartFactory`.

**Why:** This pattern centralizes part behavior and makes them composable — the loadout system applies all parts and tracks deltas for unequipping.

**Source:** [`CLAUDE.md` → Conventions`](../CLAUDE.md#conventions), [Doc 04 → Add a new Part](04-player-parts-economy.md#walkthrough-add-a-new-part)

---

### New enemy: prefer `enemy_core` + pattern Resources

**The rule:** When adding a new enemy, extend `enemy_core.gd` and declare movement/shoot behavior via the `movement` and `shoot_pattern` resource slots. Check `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/` for existing patterns before writing new code.

**Why:** Pattern Resources are composable and reusable. Bespoke `_process` logic is fine only for state machines or behavior that genuinely cannot be expressed as a pattern (continuous-effect weapons, multi-phase locomotion).

**Source:** [`CLAUDE.md` → Enemy convention`](../CLAUDE.md#enemies-scriptsenemies), [Doc 03 → Add a new enemy](03-combat-waves-enemies.md#walkthrough-add-a-new-enemy)

---

### DirAccess `res://` directory scans return empty in exported web builds

**The rule:** Runtime directory scans (`DirAccess.list_dir_begin()` on `res://`) work in the editor but return nothing in exported HTML5 builds. Use a hardcoded const manifest of file paths instead.

**Why:** Web exports package assets into a `.pck` binary; there's no filesystem to enumerate at runtime.

**Source:** [`scripts/dev/enemy_manifest.gd:4–7`](../../scripts/dev/enemy_manifest.gd) (canonical example)

---

### No silent fallbacks: delete, don't gate

**The rule:** When fixing a bug like "X should not Y", search ALL code paths (base class + subclasses) and delete the problematic behavior. Don't add a conditional that gates it.

**Why:** Silent fallbacks hide bugs and make code harder to reason about. If something shouldn't happen, make it impossible, not just rare.

**Source:** User convention

---

## Verification & Workflow

### `parse_check` is not enough — boot headless

**The rule:** Always verify code with a headless boot:
```powershell
godot --path . --headless res://scenes/<scene>.tscn --quit-after 60
```
Then grep output for `SCRIPT ERROR|Parse Error|Cannot infer|Failed to load`. Also run a full editor load (`--editor --quit-after 20`) to catch orphaned-script errors.

**Why:** `tools/parse_check.ps1` only loads scenes; it doesn't recompile GDScript. Hard compile errors (e.g., `:=` on Variant) ship undetected behind a green parse_check.

**Source:** [`docs/godot-patterns.md` → `:=` verification trap`](../godot-patterns.md#gdscript--vs--for-type-inference)

---

### House comment style: inline intent + block explanation

**The rule:** Leave two layers of comments:
1. **Inline notes on the non-obvious** — gotchas, invariants, *why this and not that*. Anything a reader can't infer.
2. **A plain-language block comment** above each meaningful chunk explaining *what it does and why*, written so a newbie Godot dev can follow along.

Never restate what the code says (`# increment the counter`). Comment as you go, riding along with real work.

**Source:** [README → House style](README.md#house-style-for-the-code-you-write), [`scripts/director.gd`](../../scripts/director.gd) (good example)

---

## Where the Rules Live

- **`CLAUDE.md`** (repo root) — authoritative house rules, architecture, conventions, and autoloads.
- **`docs/godot-patterns.md`** — running log of Godot engine quirks we've been bitten by.
- **`docs/contributing/` (this folder)** — human-readable tour and walkthroughs for each subsystem.
