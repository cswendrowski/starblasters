# HUD Light Patterns System Design

**Date:** 2026-05-28  
**Status:** Approved

## Goal

A reusable `HudLight` static class that applies tween-driven light patterns to any `CanvasItem` node (Sprite2D dot lights, ColorRect bars, Label nodes). Replaces ad-hoc tween code in `ui.gd` and enables consistent aviation/military-inspired visual language across the HUD.

## New File

**`scripts/hud_light.gd`** — static class, no node required.

### Pattern enum

```gdscript
enum Pattern { STEADY, BLINK, PULSE, FLICKER }
```

### Public API

```gdscript
# Apply a continuous looping pattern to node. Kills any previous pattern first.
static func apply(node: CanvasItem, pattern: Pattern) -> void

# Cancel all patterns on node, restore modulate:a to 1.0.
static func stop(node: CanvasItem) -> void

# One-shot hit flash: push toward white-bright, rapid flicker, return to base.
static func hit_flash(node: CanvasItem) -> void

# One-shot pip container flash: bright white tint then return.
static func pip_flash(container: CanvasItem) -> void
```

### Pattern timing specs

| Pattern | Mechanism | Timing |
|---|---|---|
| STEADY | frame=1, no tween | — |
| BLINK | modulate:a 1.0↔0.05, sharp | 0.5s on / 0.5s off (1s cycle) |
| PULSE | modulate:a 0.2↔1.0, TRANS_SINE EASE_IN_OUT | 1s up / 1s down (2s cycle) |
| FLICKER | 16-step random sequence, looped | 0.04–0.18s per step, alpha 1.0 (70%) or 0.05–0.4 (30%) |

FLICKER uses a seeded RNG (`seed = node.get_instance_id()`) so each node flickers distinctly but deterministically per session.

### hit_flash detail

1. Read `base_color := node.modulate` (to restore later)
2. Instantly set `node.modulate = Color(1.5, 1.5, 1.5, 1.0)` — white-bright
3. Tween `node.modulate` back to `base_color` over 0.08s (TRANS_SINE)
4. Rapid double flicker: modulate:a 1.0→0.05 (0.06s), 0.05→1.0 (0.06s), 1.0→0.05 (0.06s), 0.05→1.0 (0.08s)

Total duration: ~0.4s. Creates a separate Tween (not stored in `_pattern_tweens`) so the base pattern tween keeps running. Since both tweens may animate `modulate:a` simultaneously, the flash tween's writes take priority for ~0.4s (last-write-wins per frame in Godot 4), then the base pattern resumes normally. Visually seamless for this duration.

### pip_flash detail

1. Tween `container.modulate` to `Color(2.0, 2.0, 2.0, 1.0)` over 0.03s — instant white flare
2. Tween back to `Color(1.0, 1.0, 1.0, 1.0)` over 0.25s (TRANS_QUAD EASE_OUT)

Total duration: ~0.28s. Applied to the pip container Control node (not individual pips).

### Internal tween management

```gdscript
static var _pattern_tweens: Dictionary = {}  # node_id (int) -> Tween
```

`apply()` kills the existing tween for that node before creating a new one. `stop()` kills and removes. Hit flash creates a separate Tween (not stored in `_pattern_tweens`) so it doesn't cancel the base pattern.

## Changes to `scripts/ui.gd`

### 1. Pip containers

In `_install_hud()`, wrap shield and hull pips in dedicated `Control` nodes:

```gdscript
var _shield_pip_container: Control = null
var _hull_pip_container: Control = null
```

Build `_shield_pip_container` and `_hull_pip_container` as plain `Control` children of `_hud_root_node`. Add pip Sprite2Ds to the container, not directly to `_hud_root_node`. Containers have `mouse_filter = IGNORE`.

Position: set `container.set_anchors_preset(Control.PRESET_FULL_RECT)` so the container fills `_hud_root_node`. Pip Sprite2Ds inside retain their absolute positions from `_mpos()` unchanged — the container is transparent layout scaffolding only.

### 2. Replace ad-hoc threat blink

Remove `_set_threat_blink()`, `_threat_blink_tween`, and all call sites. Replace with:

```gdscript
# Wave incoming, no enemies yet → blink
HudLight.apply(_threat_light, HudLight.Pattern.BLINK)

# Enemies on screen → steady
HudLight.apply(_threat_light, HudLight.Pattern.STEADY)

# Level cleared, no wave → off
HudLight.stop(_threat_light)
_threat_light.frame = 0
```

### 3. Critical flicker

When `update_hull(max, value)` is called and `float(value)/float(max) <= 0.5`:
- Apply FLICKER to `_fire_light` and `_threat_light`

When hull recovers above 50%:
- Re-apply STEADY (or BLINK if wave is spawning) to those lights

Track this in `_hull_crit: bool` to avoid re-applying on every `update_hull` call.

### 4. Pip hit flash

In `update_shield(max, value)`:
- Track `_prev_shield: int`
- If `value < _prev_shield` (damage): `HudLight.pip_flash(_shield_pip_container)`

In `update_hull(max, value)`:
- Track `_prev_hull: int`
- If `value < _prev_hull` (damage): `HudLight.pip_flash(_hull_pip_container)`

### 5. Hit flash on indicator lights

When player takes damage (via the `damaged` signal — same signal hologram_hud uses):
- Connect `player.damaged` in `bind_player()`
- In `_on_player_damaged(amount)`: call `HudLight.hit_flash()` on `_fire_light` and `_threat_light`

## Out of scope (future TODO)

- Systems-failing FLICKER on pip containers (apply `HudLight.apply(_shield_pip_container, FLICKER)` — trivial with containers in place, deferred until Roman wants it)
- Pattern application to bounty label or other non-dot elements
