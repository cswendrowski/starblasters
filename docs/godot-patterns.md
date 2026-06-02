# Godot 4 Patterns & Gotchas

Running log of engine-specific constraints discovered during Starblaster development.
**Add to this file whenever a bug turns out to be a Godot quirk rather than a logic error.**

---

## CanvasLayer does not inherit parent transforms

**Pattern:** `CanvasLayer` nodes bypass the 2D transform hierarchy entirely. If you scale a parent Node2D or CanvasLayer, child CanvasLayer nodes are NOT affected — they always render in viewport-absolute coordinates.

**Gotcha:** Wrapping a backdrop coordinator (which has CanvasLayer children) in a scaled CanvasLayer does nothing to the inner layers.

**Fix:** To scale the entire canvas including CanvasLayer children, change `Window.content_scale_size` (via `HdViewportScope`) or use a `SubViewport` that contains the coordinator.

**Discovered:** 2026-05-29, Parallax V4 tuner

---

## Control anchors don't work inside Node2D parents

**Pattern:** A `Control` node (ColorRect, Label, Button, etc.) with `anchors_preset = 15` (PRESET_FULL_RECT) will have size **0×0** if its parent is a `Node2D` (including `Parallax2D`).

Anchors on Controls work relative to the **parent Control's rect**. Node2D doesn't have a rect, so there's nothing to anchor to.

**Fix:** Use explicit `offset_right` / `offset_bottom` instead:
```gdscript
# Inside a Parallax2D or other Node2D:
rect.offset_right  = 480.0
rect.offset_bottom = 270.0
```
Or set `size` directly in code: `rect.size = Vector2(480, 270)`.

**Exception:** Controls that are direct children of `CanvasLayer` DO get the viewport rect as their parent rect — anchors work there.

**Discovered:** 2026-05-29, Parallax V4 stars layer (ColorRect inside Parallax2D)

---

## PixelPlanets: `_apply_pixel_parity()` must be called AFTER `add_child()`

**Pattern:** The pixel parity system calls `set_pixels(px)` on a PixelPlanets node, which resizes its internal `ColorRect` children. It then calls `_reset_colorrect_sizes()` to restore them. This reset uses Godot's node tree — the ColorRect children must exist (i.e., `_ready()` must have run) before the reset can work.

**Gotcha:** Calling `_apply_pixel_parity(p, size)` **before** `add_child(p)` means the planet's `_ready()` hasn't fired yet. The ColorRect children don't exist, so the reset is a no-op. When `add_child(p)` fires `_ready()`, PixelPlanets re-initializes the ColorRects at the wrong size.

**Fix:**
```gdscript
add_child(p)                          # ← _ready() fires here, initializes ColorRects
_apply_pixel_parity(p, actual_size)   # ← now safe to reset them
```

**Commit fix:** 7d834da

**Discovered:** 2026-05-29, Parallax V4 planet layer

---

## SubViewportContainer.stretch resizes the SubViewport (use stretch_shrink to keep native res)

**Pattern:** `SubViewportContainer.stretch = true` does NOT scale a fixed-size SubViewport up to fill the container. It *resizes* the SubViewport's render resolution to `container_size / stretch_shrink`. With the default `stretch_shrink = 1` and a 1920×1080 container, your SubViewport becomes 1920×1080 — any `sub_viewport.size = Vector2i(480, 270)` you set manually is overridden.

**Gotcha:** Content authored for 480×270 (positions, sizes) then renders into a 1920×1080 viewport and clusters in the top-left quarter.

**Fix:** To render at 480×270 and display at 1920×1080 (4× upscale):
```gdscript
container.stretch = true
container.stretch_shrink = 4   # 1920/4 = 480 → renders at 480×270
container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel-art upscale
```

**Discovered:** 2026-05-29, Parallax V4 tuner (backdrop appeared in top-left quarter)

---

## Duplicate materials before setting per-instance shader params

**Pattern:** A `.tscn` that defines its material as an inline `[sub_resource type="ShaderMaterial"]` (without `resource_local_to_scene = true`) shares ONE material across every instance of that scene. Calling `material.set_shader_parameter(...)` on any instance writes to the shared material — last-write-wins, so all instances end up rendering with the final value.

**Symptom:** You seed each instance differently (`set_seed(randi())` per asteroid) but they all look identical. The seeds ARE varying; the material isn't.

**Fix:** Duplicate the material per-instance before setting any shader params:
```gdscript
var inner := node.get_node_or_null("Asteroid")  # the CanvasItem holding the material
if inner != null and inner.material != null:
    inner.material = inner.material.duplicate()
# now set_seed / set_pixels / set_shader_parameter only affect THIS instance
```

**Discovered:** twice — sector map V3 (planet shader params), then Parallax V4 (every asteroid identical because Asteroid.tscn's ShaderMaterial is a shared inline SubResource). PixelPlanets/Asteroid scenes all ship shared inline materials — always duplicate when spawning more than one.

---

## Constant fallback seed → procgen looks identical in dev tools

**Pattern:** Procedural generators that seed from an autoload (`Run.run_seed`) often fall back to a hardcoded constant when that autoload is absent. Dev tools (tuners, capture scripts, isolated test scenes) usually run WITHOUT the gameplay autoloads — so they all get the same constant seed and every "Generate New" produces a byte-identical result. The generation code looks broken ("nothing randomizes") when it's actually fine — it's just being fed one frozen seed.

**Fix:** When the seed source autoload is absent, fall back to a time-based seed (`Time.get_ticks_usec()`) rather than a constant, so dev-tool regeneration actually varies. Keep the deterministic autoload seed for real gameplay.

```gdscript
var seed_val := int(Time.get_ticks_usec())   # varies in tuner/capture
if has_node("/root/Run"):
    seed_val = Run.run_seed + Run.sectors_cleared * 9973  # deterministic in-game
```

**Discovered:** 2026-05-29, Parallax V4 (every tuner "Generate New" repeated one fixed backdrop because seed fell back to 12345 with no Run)

---

## CanvasLayer `scroll_rate`/drift defaults to 0 — scrolling layers must set it explicitly

**Pattern:** When a layer's scroll is driven by a coordinator reading `layer.scroll_rate` (or any exported drift multiplier defaulting to 0.0), a layer scene that omits the override sits frozen even if it's in the scroll list.

**Gotcha:** Adding a layer to the coordinator's `_scroll_layers` array is necessary but NOT sufficient — the layer's `scroll_rate` must be a non-zero override in its `.tscn`, or `scroll(drift × 0.0)` moves it nothing.

**Discovered:** 2026-05-29, Parallax V4 planet layer (added to scroll list but scroll_rate defaulted to 0.0)

---

## `HdViewportScope` + CanvasLayer backdrop = wrong coordinate space

**Pattern:** `HdViewportScope` changes `content_scale_size` to 1920×1080. This makes all CanvasLayer nodes operate in 1920×1080 coordinate space. If your backdrop is designed for 480×270 (planetary sizes, asteroid positions, starfield density), it will render at 1920×1080 — elements appear in the wrong positions and at the wrong sizes.

**Fix:** To show a 480×270 gameplay-scale backdrop inside an HD tuner:
1. Use a `SubViewport` at size 480×270 containing the backdrop coordinator.
2. Display it via a `SubViewportContainer` with `stretch = true` at 1920×1080 (4× scale).
3. CanvasLayer children of nodes inside a SubViewport render into that SubViewport's canvas correctly.

**Discovered:** 2026-05-29, Parallax tuner V4

---

## Parallax2D scroll requires manual `scroll_offset` nudge if no camera

**Pattern:** `Parallax2D.scroll_scale` controls how much the node moves relative to camera scroll. If there's no camera (or the camera is static), `Parallax2D` doesn't scroll automatically.

**Fix:** Manually increment `parallax_node.scroll_offset += Vector2(0, delta_y)` each frame for the desired scroll effect.

**Discovered:** 2026-05-29, Parallax V4 stars layer

---

## `_apply_variant()` in BaseBullet overwrites scene-level property overrides

**Pattern:** If you set `speed = 300.0` as a property override in an inherited `.tscn`, `BaseBullet._ready()` calls `_apply_variant()` which overwrites that value with `variant.speed`. The scene override is visible in the editor but has no effect at runtime.

**Why it's still useful:** The `.tscn` override is for **editor inspection only** — it makes the properties visible in the Inspector so designers can verify configuration without running the game.

**Discovered:** 2026-05-29, enemy bullet variant scenes

---

## Shader UV stretch on non-square viewports

**Pattern:** A shader that computes star/particle positions using `UV * vec2(density, density)` will produce equal spacing in UV space, but UV space is not square on a 480×270 (16:9) viewport — UV.x covers 480px and UV.y covers 270px. This causes features to appear stretched horizontally (wider than tall).

**Fix:** Compensate with aspect ratio:
```glsl
vec2 uv = UV * vec2(density * (480.0 / 270.0), density);
// OR use equal physical-pixel density:
vec2 uv = UV * vec2(density, density * (270.0 / 480.0));
```
For star fields specifically, the V3 procedural approach (random `ColorRect` positions floored to pixel grid) avoids this entirely.

**Discovered:** 2026-05-29, `starfield.gdshader` — `UV * vec2(density, density * 1.25)` without aspect correction

---

## Backdrop CanvasLayers must be negative to stay below UI

**Pattern:** UI scenes (main menu, HUD, overlays) render at CanvasLayer 0 (default) or higher (Glass=1, HUD=5, Outline=10). Backdrop/parallax CanvasLayers set to 0 or positive will render ON TOP of menus and HUD.

**Fix:** Keep all backdrop/parallax CanvasLayers at negative values (-10 through -1). The composite/grade layer should be the least-negative (closest to 0, e.g., -1). Deepest content (stars) gets the most-negative value.

**Layer assignments for V4 backdrop:**
- -10: Stars, -8: Planet, -6: Stellar Far, -5: Mid, -4: Near, -2: Streaks, -1: Composite

**Discovered:** 2026-05-29, Parallax V4 composite at layer 2 rendered over main menu

---

## GDScript `:=` vs `= ` for type inference

**Pattern:** `var x = value` generates `UNTYPED_DECLARATION` warnings in Godot 4.6+. Use `:=` for type inference (`var x := value`) or explicit types (`var x: Type = value`).

- `var x = null` → can't infer from null; use `var x: Node = null`
- `var x = []` → can't infer element type; use `var x: Array = []` or `var x: Array[Type] = []`
- `var x := SomeFunc()` → infers the return type of `SomeFunc()`

**Project-wide:** Added `[gdscript] warnings/return_value_discarded=0` to `project.godot` to suppress the 246 false-positive warnings from `.connect()` calls.

**Discovered:** 2026-05-29, warning sweep

**⚠️ DANGER — `:=` on a Variant value is a HARD COMPILE ERROR, not a warning.** A blanket `var x = …` → `var x := …` migration WILL break the build wherever the right-hand side is Variant-typed: a call on an untyped variable, a function with no return-type annotation, an untyped array index, `get_node_or_null(...)` on an untyped var, etc. Godot reports "Cannot infer the type of X because the value doesn't have a set type." Only use `:=` where the RHS type is statically known; otherwise leave `var x = …` (untyped — a benign warning) or add an explicit `var x: Type = …`.

**Verification trap:** `tools/parse_check.ps1` (scene-load check) gave a FALSE PASS on these errors — it didn't recompile the scripts the way a real boot does. **To verify GDScript actually compiles, boot the scene headless** (`godot --path . --headless res://scenes/<scene>.tscn --quit-after 60` and grep for `SCRIPT ERROR|Parse Error|Cannot infer|Failed to load`), not just parse_check. A blanket `:=` migration broke `main.tscn` (New Game crash) and sat undetected behind a green parse_check until playtest. **Discovered:** 2026-05-29.

---

## Boss stats must be set before `super._ready()`

**Pattern:** Boss scripts that extend `boss.gd` must set `hull`, `max_hull`, `max_shield`, `shield_ring_size`, etc. **before** calling `super._ready()`. The base class reads these values in `_ready()` to initialize the shield ring and health bar.

**Gotcha (historical):** Setting stats after `super._ready()` via the `<= 0 ? default` pattern caused a 1-HP bug where the boss appeared to die on any hit.

**Discovered:** Earlier session, documented here for reference.

---

## World-space trails: `top_level` Line2D fed global points

**Pattern:** For a trail/contrail/exhaust plume that should hang in **world space** (lag behind a moving emitter, not ride the parent's transform), make the `Line2D` `top_level = true` and set its `points` directly from **global** coordinates (`marker.global_position`, or `nozzle + dir * len`). `top_level` makes the node ignore its parent's transform, so global points render where you put them — no `to_local()` needed.

**Gotcha it avoids:** The player focus trail parents a `Line2D` to `get_parent()` and converts via `get_parent().to_local(gp)` — which only works because that parent happens to be a `Node2D`. Reusing that on a node whose parent might be a plain `Node`/`Window` throws "Nonexistent function 'to_local'". `top_level` + global points sidesteps the dependency entirely.

**Z-order:** a `top_level` line still inherits z-ordering — set `z_index` to sit it in front of / behind the hull as intended (the bomber's engine plumes render at `z_index = 1`, on top of the sprite).

**Example:** `enemy_bomber.gd` (twin engine plumes).

---

## Aim by rotating the hull, not by steering the projectile

**Pattern:** To make an enemy "aim," rotate the **whole sprite** toward the target and fire the weapon along a **fixed local-forward** direction (out the nose/emitter), rather than computing a per-shot aim vector while the sprite sits still. The art stays coherent — the emitter, muzzle, and shot all line up with the hull — and the visible turn *is* the telegraph.

- Forward is a constant in local space (e.g. `FWD_LOCAL = Vector2(0, -1)` for a sprite drawn facing up). The shot/beam direction in the world is just `FWD_LOCAL.rotated(rotation)`, or — for a `Line2D` beam that's a child of the hull — author the points in local space and let the hull's `rotation` carry them.
- Rotate toward target with a **speed limit** so tracking stays dodgeable: `rotation += clampf(angle_difference(rotation, target_rot), -SPEED*delta, SPEED*delta)`, where `target_rot = atan2(dir.x, -dir.y)` makes local-up point along `dir`.
- This is `auto_rotate = false` territory — you own `rotation`, so the base auto-rotate (which faces *movement*) stays out of the way.

**Examples:** `enemy_gunship.gd` (hull rotates to player, rockets fire along facing), `enemy_beam_shooter.gd` (hull rotates, beam exits the front maw).
