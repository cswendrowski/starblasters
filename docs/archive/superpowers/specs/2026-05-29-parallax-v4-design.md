**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: parallax V4 shipped (scripts/parallax/backdrop_coordinator.gd).
Do not cite as a to-do.

# Parallax V4 — Per-Layer CanvasLayer Architecture

**Status:** Spec approved 2026-05-29. Supersedes V3 (`scripts/parallax/galaxy_backdrop_v3.gd`).

## Problem with V1/V3

V1 (current active `scripts/galaxy_backdrop.gd`) and V3 both use a flat Node2D tree. Color grading is done via a BLEND_MODE_MUL `ColorRect` ("AnchorTint") painted last — it hits every layer simultaneously with the same tint. Wanting to grade nebula differently from asteroids, or stars differently from planets, requires fighting the global pass with per-node `modulate` compensation.

V3's attempt at per-child `modulate` tinting works but is fragile — the CanvasGroup+tint-shader pipeline was abandoned after it produced opaque backing sheets in Godot 4.3.

## V4 Core Idea

Every visual layer is its own `CanvasLayer` scene with a single `CanvasModulate` node inside it. CanvasModulate scoped to a CanvasLayer affects only that layer's content. A thin coordinator script instantiates all layer scenes, drives scroll via `CanvasLayer.offset.y`, and routes spawning into the right layers.

## Layer Stack (bottom → top) — 7 scenes

| Layer # | Scene | Content | Default scroll rate |
|---------|-------|---------|---------------------|
| -5 | `layer_stars.tscn` | Black fill ColorRect + two `starfield.gdshader` Parallax2D sub-layers (far/near). Both starfields live in one scene with independent Parallax2D scroll scales. | 0.02× (far), 0.08× (near) |
| -3 | `layer_planet.tscn` | All PixelPlanets objects: planets, stars, black holes, Galaxy. Plus companion bodies and POI moons. Spawner script handles pixel parity. | 0.10× |
| -2 | `layer_stellar_far.tscn` | Far-depth band: small asteroids, nebula dust, recycling enemy ships, decorative bg mines, and any future far-field dressing. Dark silhouette. | 0.25× |
| -1 | `layer_stellar_mid.tscn` | Mid-depth band: medium asteroids, nebula wisps, more active dressing. | 0.55× |
| 0 | `layer_stellar_near.tscn` | Near-depth band: larger asteroids, brightest. Fastest scroll. | 1.00× |
| 1 | `layer_streaks.tscn` | Warp streaks (`GPUParticles2D`) and any other close-to-player decorative effects. | N/A (particle velocity) |
| 2 | `layer_composite.tscn` | Final atmospheric grade: full-vp `ColorRect` BLEND_MODE_MUL + vignette `Sprite2D`. CanvasModulate here controls global mood tint. | 0 (static) |

**Total: 7 CanvasLayer scenes.**

### Why `layer_stars.tscn` contains two sub-layers

The two starfield shader rects scroll at different rates (0.02× and 0.08×) to give depth. In V4 these live as two `Parallax2D` children inside the single `layer_stars` CanvasLayer — the Parallax2D handles the differential scroll internally, and one CanvasModulate on the scene colors the whole star layer. No need for a separate scene per star depth.

### What goes in the Stellar layers

The three Stellar layers are general-purpose depth bands. The content router decides what to place where — currently asteroids, nebula dust, and bg mines, but the design deliberately leaves room for recycling enemy ships, floating debris, or other future decorative objects at the appropriate depth. Each band has its own CanvasModulate so far-field objects can be desaturated/darkened while near-field pops.

### Why keep `layer_composite`

Without it, the global atmospheric tint (the "space feels blue/orange today" pass) would require touching all five content layers every time the sector mood shifts. `layer_composite` is one knob: `compositor.modulate_color = planet_tint`. Per-layer CanvasModulates handle depth/content variation; composite handles global mood. The vignette lives here too — it sits atop everything and is part of the final image grade.

## Per-Layer Color Grading

Each layer scene has a `CanvasModulate` node and exports:
```gdscript
@export var modulate_color: Color = Color.WHITE
```

In `_ready()`: `$CanvasModulate.color = modulate_color`. The coordinator sets per-layer tints from the planet-derived dominant color at spawn time:

```gdscript
layer_stellar_far.modulate_color  = planet_tint.lerp(Color.WHITE, 0.75)  # subtle depth tint
layer_stellar_near.modulate_color = planet_tint.lerp(Color.WHITE, 0.50)  # stronger near
layer_composite.modulate_color    = Color.WHITE.lerp(planet_tint, tint_alpha)  # global mood
```

The Parallax Tuner exposes each layer's CanvasModulate as a color picker. One picker per scene.

## Coordinator (`backdrop_coordinator.gd`)

Thin script. Responsibilities:

1. **Instantiate** all 7 layer scenes as children
2. **Drive scroll**: each frame, `layer.offset.y += drift_speed * layer.scroll_rate * delta` for scrolling layers; `layer_stars` internal Parallax2D handles its own differential scroll
3. **Route spawning**: `spawn_planet(config)` → layer_planet; `populate_stellar(band, config)` → stellar far/mid/near; `spawn_streaks(config)` → layer_streaks
4. **Apply tints**: after planet type is determined, sets `modulate_color` on each layer per the tint formula above
5. **Reset**: clears all layers and re-populates from `Run.current_stellar`

Exported knobs (mirrors current `galaxy_backdrop.gd`):
```gdscript
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

V1 uses `position.y += drift_speed * drift_mult * delta` on every child node with a `drift` meta. V4 replaces this with `CanvasLayer.offset.y` per layer.

Each layer scene exports `@export var scroll_rate: float`. The coordinator drives:
```gdscript
for layer in _scroll_layers:
    layer.offset.y += drift_speed * layer.scroll_rate * delta
```

When `layer.offset.y` exceeds `RESET_THRESHOLD`, the layer's spawner script re-scatters its content at the top. Individual asteroid rotation is driven by a script on each asteroid node, independent of layer scroll.

`layer_stars.tscn` is handled differently: its two `Parallax2D` children have their own `scroll_scale` properties, and the Parallax2D responds to the viewport camera offset (or a manual `scroll_offset` nudge each frame). No `offset.y` needed on the stars CanvasLayer itself.

## Nebula

Nebula dust lives inside the Stellar layers as `ColorRect` children with `nebula2.gdshader`, not a dedicated nebula scene. The Stellar Far/Mid bands each get one nebula rect when a nebula band is active for the sector. The Stellar band's CanvasModulate tints the nebula along with the asteroids in that band — no separate per-nebula tint needed.

This simplifies the architecture: nebula is just another piece of content placed by `populate_stellar()`, not a separate layer.

## Star Rendering

Keep V1's `starfield.gdshader`. Two `ColorRect`s with different densities/thresholds live in `layer_stars.tscn` as children of two `Parallax2D` nodes. Shader `scroll_speed = 0` — scroll is driven by the Parallax2D `scroll_offset` nudged each frame by the coordinator.

## Planet Layer

`layer_planet.tscn` contains a spawner script that:
- Instantiates the PixelPlanets scene based on planet index
- Applies pixel parity (`_apply_pixel_parity` after `add_child`)
- Spawns companion bodies and POI moons as children
- All planet objects drift at the same rate via the layer's `offset.y`

Pixel parity logic moves intact from `galaxy_backdrop.gd`.

## Parallax Tuner Integration

The tuner walks the coordinator's CanvasLayer children and exposes one colorization picker per scene. The existing JSON persistence and `Copy GDScript` button work without changes to the tuner contract — just the enumerate step changes from "direct Node2D children" to "CanvasLayer children of coordinator".

## What Changes vs V1

| V1 | V4 |
|----|-----|
| Flat Node2D tree, 30+ direct children | Coordinator with 7 CanvasLayer scenes |
| Color grade: BLEND_MODE_MUL AnchorTint (hits all layers equally) | CanvasModulate per-layer, composite layer for global mood |
| Scroll: `drift` meta per-node | `CanvasLayer.offset.y` per-layer |
| Nebula: dedicated layers with own tint management | Nebula: content placed in Stellar bands, tinted with the band |
| Per-node `modulate` depth silhouette | Per-layer CanvasModulate on Stellar Far/Mid/Near |
| Pixel parity in coordinator | Pixel parity in planet layer scene |
| No designer-visible structure in editor | Each layer is a named scene file |

## What's Preserved from V1

- All visual content: stars, nebula, planets, asteroids, warp streaks, vignette
- Background mines and asteroid field density multiplier (placed in Stellar bands)
- POI moons, companion bodies, binary stars
- Pixel parity system
- All `@export` tuning knobs (on coordinator)
- Deterministic seeding from `Run.run_seed`

## File Layout

```
scenes/parallax/
  backdrop_coordinator.tscn
  layers/
    layer_stars.tscn
    layer_planet.tscn
    layer_stellar_far.tscn
    layer_stellar_mid.tscn
    layer_stellar_near.tscn
    layer_streaks.tscn
    layer_composite.tscn

scripts/parallax/
  backdrop_coordinator.gd
  layer_base.gd           ← base class: scroll_rate, modulate_color, CanvasModulate wiring
  layer_planet.gd         ← planet spawner + pixel parity
  layer_stellar.gd        ← asteroid/nebula/mine scatter + respawn (shared by all 3 bands)
  layer_stars.gd          ← Parallax2D scroll nudge
  layer_streaks.gd        ← GPUParticles2D warp config
```

## Callers

All callers that currently `set_script(BACKDROP_SCRIPT)` switch to:
```gdscript
var bd := preload("res://scenes/parallax/backdrop_coordinator.tscn").instantiate()
add_child(bd)
```

Scripts to update: `scripts/main.gd`, `scripts/main_menu.gd`, `scripts/dev/parallax_tuner.gd`, `scripts/dev/asteroid_lab.gd`.
