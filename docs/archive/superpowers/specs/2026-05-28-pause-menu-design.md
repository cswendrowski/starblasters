**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: pause menu shipped (scenes/pause_menu.tscn).
Do not cite as a to-do.

# Pause Menu Redesign — Spec

## Goal

Replace the oversized pause overlay and cramped options panel with:
1. A slim 3-button pause overlay (MAIN MENU / OPTIONS / BACK)
2. A full-width 2-column HD options screen with all controls visible at once

## Pause Overlay

**Scene:** `scenes/pause_menu.tscn` + `scripts/pause_menu.gd`

Narrow centered panel (~160px wide), dark dim backdrop. ESC toggles open/close.

Buttons (top→bottom):
- **MAIN MENU** — retains mid-level warning ("Leaving will scrap progress in this level")
- **OPTIONS** — opens the options screen lazily
- **BACK** — unpauses + hides

No Quit button (web export target). No PAUSED header. No status readout.

Layer: 10 (unchanged). `process_mode = ALWAYS` (unchanged).

## Options Screen

**File:** `scripts/ui/options_overlay.gd` (rewritten in-place, API preserved)

Full-viewport CanvasLayer at layer 91. Keeps the existing `static func open(parent) -> CanvasLayer` factory — all current callers (main_menu.gd, pause_menu.gd, sector_map_hd.gd, sector_map_v3.gd) work unchanged.

Layout: PanelContainer centered, two-column HBox inside:

**Left column (Audio + Display):**
- Master Volume slider (0–1, %)
- Music Volume slider (0–1, %)
- Screen Shake slider (0–1, %)
- Fullscreen toggle (CheckButton)
- Font face dropdown (Pixel Operator / Pixelify Sans)

**Right column (Controls):**
- 6 rebind rows: shoot / shoot2 / shoot_nose / focus / primary_swap / autofire_toggle
- Click to rebind (keyboard only); ESC cancels

**BACK** button below both columns, centered. Returns to previous screen (queue_free).

ESC key also triggers Back.

## What Changes

| File | Change |
|------|--------|
| `scenes/pause_menu.tscn` | Remove Quit btn, remove Status/header nodes; keep Dim + Center + VBox + 3 btns |
| `scripts/pause_menu.gd` | Remove `_install_options_button`, `_quit`, status nodes; add `_open_options` |
| `scripts/ui/options_overlay.gd` | Replace single-column scroll with 2-column panel; remove "Return to Main Menu" btn |

No new files needed. All existing callers continue using `OptionsOverlay.open(self)`.
