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

---

## Boss stats must be set before `super._ready()`

**Pattern:** Boss scripts that extend `boss.gd` must set `hull`, `max_hull`, `max_shield`, `shield_ring_size`, etc. **before** calling `super._ready()`. The base class reads these values in `_ready()` to initialize the shield ring and health bar.

**Gotcha (historical):** Setting stats after `super._ready()` via the `<= 0 ? default` pattern caused a 1-HP bug where the boss appeared to die on any hit.

**Discovered:** Earlier session, documented here for reference.
