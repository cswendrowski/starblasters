**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: HUD shipped (scripts/hud/ui.gd).
Do not cite as a to-do.

# Marker-Driven Live HUD

**Date:** 2026-05-28  
**Status:** Approved

## Goal

Replace the BoxContainer-layout HUD in `ui.gd` with a fully marker-driven HUD that reads element positions from `Marker2D` nodes in `ui.tscn` — the same pattern the sector map uses. Moving a marker in the editor repositions the corresponding HUD element at runtime with no code change.

## What Is Removed

- `BoxContainer` + `HullShieldRow` layout container and all child layout nodes
- `HullPipsCls` HBoxContainer (replaced by absolute-positioned dot sprites)
- `TextureProgressBar` shield bar (replaced by 3×10 pip sprite rows)
- `ScoreCounter` (legacy 8×8 pixel counter)
- `WaveLabel`
- `_install_ammo_row()` / ammo label
- `_install_super_pips()` / super-charge pip strip
- Old `_install_focus_bar()` (rebuilt from markers)
- Old `_install_weapon_hints()` / `_refresh_weapon_hints()` (rebuilt from markers)

## What Is Kept

- `ui.gd` script name and attachment — no main.tscn surgery required
- Public API: `bind_player()`, `update_hull()`, `update_shield()`, `update_score()`
- All signal handlers: `_on_wave_started_threat`, `_on_level_cleared_threat`, `_on_ammo_changed`, `_on_secondary_ammo_changed`, `_on_super_charges_changed`, `_on_focus_charge_changed`
- `HologramHUDCls` applied to the HUD root (no change)
- `_process()` logic for weapon lights, blaster status, fire light, threat light

## Architecture

All HUD elements are built in `_install_hud()` (replacing both `_ready()`'s layout code and `_install_new_hud()`) onto a single `CanvasLayer` at layer 5.

### Marker-reading helper

```gdscript
func _mpos(path: String, fallback: Vector2) -> Vector2:
    if has_node(path):
        return (get_node(path) as Marker2D).global_position
    return fallback
```

All element positions go through `_mpos()`. Uses `global_position` so nested markers (e.g. `shield_label/shield_pip_row_1`) automatically return absolute viewport coordinates. Every call has a hardcoded fallback (absolute viewport position) so the HUD renders correctly if a marker is missing or renamed.

### Element inventory

**Left gutter**

| Element | Marker path | Fallback |
|---|---|---|
| "SHIELD" label | `shield_label` | (16, 16) |
| Shield pip row 1 | `shield_label/shield_pip_row_1` | (16, 24) |
| Shield pip row 2 | `shield_label/shield_pip_row_2` | (16, 40) |
| Shield pip row 3 | `shield_label/shield_pip_row_3` | (16, 56) |
| "HULL" label | `hull_label` | (16, 72) |
| Hull pip row | `hull_label/hull_pip_row_1` | (16, 88) |
| Hull annunciator sprite | `hull_annuciator` | (16, 104) |
| "FIRE" label | `fire_label` | (48, 104) |
| Fire light | `fire_label/fire_light` | (64, 104) |

**Right gutter**

| Element | Marker path | Fallback |
|---|---|---|
| "THREAT" label | `threat_label` | (376, 72) |
| Threat light | `threat_label/threat_light` | (376, 80) |
| "ARMAMENT" label | `armanent_label` | (392, 16) |
| "BLASTER" label | `pri_blaster_label` | (392, 24) |
| Blaster weapon_key hint | `pri_blaster_label/weapon_key` | (360, 24) |
| Blaster light | `pri_blaster_label/weapon_light` | (376, 24) |
| Blaster status label | `pri_blaster_label/blaster_status` | (456, 24) |
| PRI weapon name label | `pri_blaster_label/pri_weapon_label` | (392, 32) |
| PRI weapon_key hint | `pri_blaster_label/pri_weapon_label/weapon_key` | (360, 32) |
| PRI weapon light | `pri_blaster_label/pri_weapon_label/weapon_light` | (376, 32) |
| PRI ammo count | `pri_blaster_label/pri_weapon_label/pri_ammo_count` | (456, 32) |
| SEC weapon name label | `pri_blaster_label/sec_weapon_label` | (392, 40) |
| SEC weapon_key hint | `pri_blaster_label/sec_weapon_label/weapon_key` | (360, 40) |
| SEC weapon light | `pri_blaster_label/sec_weapon_label/weapon_light` | (376, 40) |
| SEC ammo count | `pri_blaster_label/sec_weapon_label/sec_ammo_count` | (456, 40) |
| SUP weapon name label | `pri_blaster_label/sup_weapon_label` | (392, 48) |
| SUP weapon_key hint | `pri_blaster_label/sup_weapon_label/weapon_key` | (360, 48) |
| SUP weapon light | `pri_blaster_label/sup_weapon_label/weapon_light` | (376, 48) |
| SUP ammo bars | `pri_blaster_label/sup_weapon_label/sup_ammo_bars` | (456, 48) |

**Bottom**

| Element | Marker path | Fallback |
|---|---|---|
| "BOUNTY" label | `bounty_label` | (392, 240) |
| Bounty value | `bounty_label/bounty_count` | (448, 240) |
| "FOCUS" label | `focus_label` | (8, 247) |
| Focus bar background | `focus_bar` | (8, 256) |

### New Marker2Ds to add to ui.tscn

These are added to `ui.tscn` at their current rendered positions; Roman adjusts manually:

| Node name | Parent | Position |
|---|---|---|
| `focus_label` | `UI` (root) | (8, 247) |
| `focus_bar` | `UI` (root) | (8, 256) |
| `weapon_key` | `pri_blaster_label` | (-32, 0) |
| `weapon_key` | `pri_blaster_label/pri_weapon_label` | (-32, 0) |
| `weapon_key` | `pri_blaster_label/sec_weapon_label` | (-32, 0) |
| `weapon_key` | `pri_blaster_label/sup_weapon_label` | (-32, 0) |

### Shield pips

Shield has 3 rows of 10 `Sprite2D` dots using `hud_dot_light.png` (hframes=2, frame 0=off, frame 1=on), tinted blue. Row starting positions come from the three `shield_pip_row_*` markers. Within each row, pips are spaced 10px apart (DOT_FW=8 + 2px gap).

`update_shield(max, value)` fills proportionally across all 30 pips: `filled = round(float(value) / float(max_value) * 30)`. Row 1 fills first (pips 0–9), then row 2, then row 3. This keeps the display readable whether max is 1 or 30.

### Hull pips

10 `Sprite2D` dots using `hud_dot_light.png`, tinted red. Starting position from `hull_label/hull_pip_row_1`. Same 10px spacing. `update_hull(max, value)` fills `round(float(value)/float(max_value)*10)` pips.

### Weapon key hints

Labels at each `weapon_key` marker. Text = `[Key]` where Key is the first keyboard binding for the corresponding action (`shoot` for blaster/PRI, `shoot2` for SEC, `shoot_nose` for SUP). Uses `_action_key_label()` (retained from current code). Color = white at 50% alpha.

### Ammo counts

- PRI ammo: Label at `pri_ammo_count` marker. Shows current ammo for non-blaster cannons; hidden when blaster active (infinite). Updated by `_on_ammo_changed()`.
- SEC ammo: Label at `sec_ammo_count`. Shows secondary ammo. Updated by `_on_secondary_ammo_changed()`.
- SUP ammo: Label at `sup_ammo_bars`. Shows super charge count as "|||" style or numeric. Updated by `_on_super_charges_changed()`.

### Focus bar

Two `ColorRect` nodes (background + fill) starting at `focus_bar` marker position, fixed size 48×4px. Label at `focus_label`. `_on_focus_charge_changed(charge, max)` scales fill width. Installed during `bind_player()`.

### Bounty

Two `Label` nodes. "BOUNTY" at `bounty_label`, value at `bounty_label/bounty_count`. `update_score()` updates the value label. Color = gold.

## Data flow

```
Player signals → bind_player() wires → update_hull / update_shield / etc.
                                      → drives Sprite2D .frame on pip arrays
Run autoload  → _process() polls   → weapon lights, blaster status
Director      → wave_started/cleared → threat light blink
```

## ui.gd structure after rewrite

```
_ready()
  _install_hud()          ← builds all elements from markers
  (no BoxContainer setup)

bind_player(player)
  _wire_player_signals()
  _install_focus_bar()    ← now builds from focus_label/focus_bar markers
  seed initial state

update_hull(max, val)     ← drives _hull_pips[] array
update_shield(max, val)   ← drives _shield_pips[][] 3×10 array
update_score(val)         ← drives _bounty_value_label

_process()                ← weapon lights, blaster status, fire light, threat light
```

## Out of scope

- Super-charge pips (removed, no marker defined)
- Ammo label (removed; ammo shown inline with weapon name in armament block)
- WaveLabel / ScoreCounter (removed)
- Hologram shader application (unchanged — still applied to HUD root)
