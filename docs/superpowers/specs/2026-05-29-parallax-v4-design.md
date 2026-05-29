# Parallax V4 — Per-Layer CanvasLayer Architecture

**Status:** Spec approved 2026-05-29. Supersedes V3 (`scripts/parallax/galaxy_backdrop_v3.gd`).

## Problem with V1/V3

V1 (current active `scripts/galaxy_backdrop.gd`) and V3 both use a flat Node2D tree. Color grading is done via a BLEND_MODE_MUL `ColorRect` ("AnchorTint") painted last — it hits every layer simultaneously with the same tint. Wanting to grade nebula differently from asteroids, or stars differently from planets, requires fighting the global pass with per-node `modulate` compensation.

V3's attempt at per-child `modulate` tinting works but is fragile — the CanvasGroup+tint-shader pipeline was abandoned after it produced opaque backing sheets in Godot 4.3.

## V4 Core Idea

Every visual layer is its own `CanvasLayer` scene with a single `CanvasModulate` node inside it. CanvasModulate scoped to a CanvasLayer affects only that layer's content. A thin coordinator script instantiates all layer scenes, drives scroll via `CanvasLayer.offset.y`, and routes planet/asteroid/mine spawning into the right layers.

## Layer Stack (bottom → top)

| Layer # | Scene | Content | Default scroll rate |
|---------|-------|---------|---------------------|
| -5 | `layer_deep_space.tscn` | Black fill `ColorRect` (480×270) + star-color DeepSky bias | 0 (static) |
| -4 | `layer_stars_far.tscn` | Dense fine starfield — `starfield.gdshader` on full-vp ColorRect, density=32, threshold=0.96 | 0.02× |
| -3 | `layer_stars_near.tscn` | Sparser brighter stars, slower twinkle — density=20, threshold=0.94, brightness=1.15 | 0.08× |
| -2 | `layer_nebula.tscn` | Two `nebula2.gdshader` rects (far + near octave) — seamless scroll via `scroll_offset` driven from `offset.y` | 0.15× |
| -1 | `layer_planet.tscn` | PixelPlanets celestial + companion bodies + POI moons. Spawner script handles pixel parity. | 0.10× |
| 0 | `layer_asteroids_far.tscn` | 4× small asteroids, deep-band positions, dark silhouette | 0.25× |
| 1 | `layer_asteroids_mid.tscn` | 5× medium asteroids | 0.55× |
| 2 | `layer_asteroids_near.tscn` | 3× larger asteroids, brightest | 1.00× |
| 3 | `layer_warp.tscn` | `GPUParticles2D` warp streaks — additive vertical streaks, particle velocity drives speed | N/A (particle) |
| 4 | `layer_grade.tscn` | Global atmospheric tint — single full-vp `ColorRect` with `BLEND_MODE_MUL` + CanvasModulate. Replaces AnchorTint. | 0 (static) |
| 5 | `layer_vignette.tscn` | Radial gradient `Sprite2D` BLEND_MODE_MUL, center white → 0.74 at corners. | 0 (static) |

**Hazard-only layers** (instantiated only when needed):
- `layer_bg_mines.tscn` — decorative background mines at layers 0–2 (no collision). Inserted between near asteroids and warp.

## Per-Layer Color Grading

Each layer scene exports `@export var modulate_color: Color = Color.WHITE`. In `_ready()`, the scene assigns `CanvasModulate.color = modulate_color`. The coordinator sets this from planet-derived tints at spawn time.

```
layer_scene.modulate_color = planet_tint.lerp(Color.WHITE, 0.6)
```

This replaces all V1 per-node `.modulate` assignments. Per-layer control, zero bleed between layers.

The global atmospheric grade (layer 4) is still a full-vp MUL ColorRect — unchanged from V1 — but now it's in its own CanvasLayer so it cleanly sits atop everything and is independently tintable.

## Coordinator (`backdrop_coordinator.gd`)

Thin script, no spawning logic of its own. Responsibilities:

1. **Instantiate** all layer scenes and `add_child` them
2. **Drive scroll**: each frame, `layer.offset.y += drift_speed * layer.scroll_rate * delta`
3. **Route spawning**: exposes `spawn_planet(config)`, `spawn_asteroids(config)`, `attach_moons(config)`, `spawn_bg_mines(config)` that forward to the appropriate layer scene
4. **Apply tints**: after planet type is known, calls `set_layer_tint(layer_name, color)` on each layer
5. **Reset**: `reset()` clears all layers and re-spawns from the current `Run.current_stellar`

Exported knobs on the coordinator (mirrors current `galaxy_backdrop.gd` exports):
```
@export var drift_speed: float = 22.0
@export var planet_size: float = 240.0
@export var planet_size_variance: float = 0.35
@export var tint_alpha: float = 0.09
@export var asteroid_count: int = 3
@export var use_warp_streaks: bool = true
@export var warp_streak_count: int = 14
@export var forced_planet_idx: int = -1
@export var pixel_density: float = 1.0
```

## Scroll System

V1 uses `position.y += drift_speed * drift_mult * delta` on every child node with a `drift` meta. V4 replaces this with `CanvasLayer.offset.y`.

Each layer scene exports `@export var scroll_rate: float = 1.0`. The coordinator drives:
```gdscript
for layer in _scroll_layers:
    layer.offset.y += drift_speed * layer.scroll_rate * delta
```

No more `drift` meta per-node. Asteroids within `layer_asteroids_*.tscn` are positioned relative to the layer root; the layer itself scrolls as a unit. Individual asteroid rotation (V1's per-asteroid spin) is driven by a script on each asteroid node.

Reset: when `layer.offset.y > RESET_THRESHOLD`, the layer's spawner script re-scatters its content at the top — same as V1's per-node reset logic but now scoped to the layer.

## Nebula

Use V3's approach: `nebula2.gdshader` with `scroll_offset` uniform fed from `layer_nebula.offset.y / TILE_SIZE`. This gives seamless tiling without a separate offset tracker.

Two nebula rects (far + near) live inside `layer_nebula.tscn` and share the same scroll. The CanvasModulate on `layer_nebula` tints both at once — one color pick controls the whole nebula pass.

## Star Rendering

V4 keeps V1's shader approach (`starfield.gdshader`) over V3's procedural ColorRect nodes. Two layers (far/near) give depth. The shader drives scroll via its `scroll_speed` uniform — the layer's `offset.y` also scrolls the whole field which causes a double-scroll; use `offset.y` only and set shader `scroll_speed = 0`, OR use shader scroll exclusively and ignore `offset.y` for star layers. Decision: **use `offset.y` exclusively on star layers, shader `scroll_speed = 0`** — consistent with all other layers.

## Planet Layer

`layer_planet.tscn` contains a spawner script that:
- Instantiates the PixelPlanets scene based on planet index
- Applies pixel parity (`_apply_pixel_parity` after `add_child`)
- Spawns companion bodies and POI moons as children
- Drifts the entire planet group downward via the coordinator's `layer.offset.y`

Pixel parity logic moves intact from `galaxy_backdrop.gd`. No architectural change needed — it still operates on the instantiated Control node's ColorRect children.

## Parallax Tuner Integration

The existing Parallax Tuner (`scripts/dev/parallax_tuner.gd`) enumerates direct children of the backdrop and exposes brightness/contrast/colorization per layer. V4 exposes named CanvasLayer scenes as children of the coordinator. The tuner needs one update: it should walk the coordinator's CanvasLayer children and set `layer.modulate_color` from the colorization picker. The existing JSON persistence format and `Copy GDScript` button work unchanged.

## What Changes vs V1

| V1 | V4 |
|----|-----|
| Flat Node2D tree, 30+ direct children | Coordinator with 10 CanvasLayer scenes |
| Color grading via BLEND_MODE_MUL AnchorTint (hits all layers) | CanvasModulate per-layer + global grade layer |
| Scroll via `drift` meta per-node | `CanvasLayer.offset.y` per-layer |
| Per-node `modulate` compensation for silhouette depth | Per-layer CanvasModulate, no compensation |
| Pixel parity in coordinator | Pixel parity in planet layer scene |
| No designer-visible layer structure | Each layer is a scene file, open in editor |

## What's Preserved from V1

- All visual content: stars, nebula, planets (PixelPlanets), asteroids, warp streaks, vignette
- All hazard-specific content: bg mines, asteroid field density multiplier
- POI moons, companion bodies, binary stars
- Pixel parity system for planets
- All `@export` tuning knobs (moved to coordinator)
- Deterministic seeding from `Run.run_seed`

## File Layout

```
scenes/parallax/
  backdrop_coordinator.tscn      ← main scene (replaces galaxy_backdrop.gd)
  layers/
    layer_deep_space.tscn
    layer_stars_far.tscn
    layer_stars_near.tscn
    layer_nebula.tscn
    layer_planet.tscn
    layer_asteroids_far.tscn
    layer_asteroids_mid.tscn
    layer_asteroids_near.tscn
    layer_warp.tscn
    layer_grade.tscn
    layer_vignette.tscn
    layer_bg_mines.tscn          ← hazard-only, instantiated on demand

scripts/parallax/
  backdrop_coordinator.gd
  layer_base.gd                  ← base class: scroll_rate, modulate_color, reset()
  layer_planet.gd                ← planet spawner + pixel parity
  layer_asteroids.gd             ← asteroid scatter + respawn logic
  layer_stars.gd                 ← starfield shader driver
  layer_nebula.gd                ← nebula scroll_offset driver
  layer_warp.gd                  ← GPUParticles2D warp config
```

## Callers

All callers that currently set `node.set_script(BACKDROP_SCRIPT)` switch to:
```gdscript
var bd := preload("res://scenes/parallax/backdrop_coordinator.tscn").instantiate()
add_child(bd)
```

Scripts to update: `scripts/main.gd`, `scripts/main_menu.gd`, `scripts/dev/parallax_tuner.gd`, `scripts/dev/asteroid_lab.gd`, and any dev scenes that directly set the backdrop script.
