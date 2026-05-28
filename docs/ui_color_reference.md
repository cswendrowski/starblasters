# UI / HUD Color Reference

Source of truth: `scripts/ui/ui_theme.gd`. All menu and overlay code should import from `UiTheme` constants rather than redefining colors inline.

---

## Canonical Palette (`UiTheme`)

| Token | Value (RGBA 0–1) | Hex approx | Usage |
|---|---|---|---|
| `COLOR_TEXT` | `(0.95, 0.97, 1.00, 1)` | `#F2F7FF` | Primary body text |
| `COLOR_WHITE` | `(1.00, 1.00, 1.00, 1)` | `#FFFFFF` | Pure white — headers, highlights |
| `COLOR_ACCENT` | `(0.62, 0.82, 1.00, 1)` | `#9ED1FF` | Buttons, headers, interactive |
| `COLOR_ACCENT_DIM` | `(0.32, 0.50, 0.72, 1)` | `#5280B8` | Outlines, inactive borders |
| `COLOR_OUTLINE` | `(0.05, 0.08, 0.12, 1)` | `#0D141F` | Text outline (1 px on HUD, 3–6 px on menus) |
| `COLOR_BOUNTY` | `(1.00, 0.86, 0.42, 1)` | `#FFDB6B` | Currency / bounty — warm gold |
| `COLOR_DANGER` | `(1.00, 0.40, 0.32, 1)` | `#FF6652` | Alert red — hull < 50%, danger annunciator |
| `COLOR_DANGER_DK` | `(0.40, 0.05, 0.00, 1)` | `#660D00` | Danger outline |
| `COLOR_DISABLED` | `(0.45, 0.50, 0.58, 0.75)` | `#737F94 @75%` | Unavailable options |
| `COLOR_FAINT` | `(0.70, 0.78, 0.88, 0.70)` | `#B3C7E0 @70%` | Captions, version label, secondary info |
| `COLOR_PANEL_BG` | `(0.05, 0.07, 0.11, 0.82)` | `#0D121C @82%` | Modal/menu panel backgrounds |

---

## Extended Palette (in-game HUD + Sector Map)

These are used in `scripts/sector_map_v3.gd`, `scripts/ui.gd`, and the new HUD dot system. Add them to `UiTheme` if they are referenced in 2+ places.

| Name | Value | Hex approx | Usage |
|---|---|---|---|
| Shield blue | `(0.35, 0.65, 1.00, 1)` | `#59A6FF` | Shield pip tint (`ui.gd:144`) |
| Hull red | `(1.00, 0.30, 0.30, 1)` | `#FF4D4D` | Hull pip tint |
| Weapon green | `(0.55, 1.00, 0.50, 1)` | `#8CFF80` | Weapon names, ammo counts, HUD indicators — matches `COLOR_NODE_GREEN` in sector map |
| Sector node green | `(0.55, 1.00, 0.50, 1)` | `#8CFF80` | Cleared nodes, progress ticks in sector map |
| Boss red | `(1.00, 0.30, 0.25, 1)` | `#FF4D40` | Boss marker icons |
| Map route | `(0.32, 0.42, 0.58, 0.50)` | `#526694 @50%` | Sector map route lines |
| POI / star label | `(0.75, 0.85, 1.00, 1)` | `#BFD9FF` | Star names, POI body labels on sector map |
| Map title gold | `(1.00, 0.85, 0.30, 1)` | `#FFD94D` | Section titles in sector map modals |

---

## HUD Semantic Mapping

| HUD Element | Color | Notes |
|---|---|---|
| Shield pips (on) | Shield blue `(0.35, 0.65, 1.00)` | Lit frame |
| Shield pips (off) | Same, dark frame | Frame 0 of `hud_dot_light.png` |
| Hull pips (on) | Hull red `(1.00, 0.30, 0.30)` | Lit frame |
| Hull pips (off) | Same, dark frame | Frame 0 of `hud_dot_light.png` |
| WARN annunciator | Sprite frame 1 | `hud_annunciator_danger.png` — triggered: no shields OR hull ≤ 50% |
| DNGR annunciator | Sprite frame 2 | Triggered: hull = 0 |
| WARN+DNGR | Sprite frame 3 | Both active simultaneously |
| Weapon name | Weapon green `(0.55, 1.00, 0.50)` | |
| Ammo count / indicator | Weapon green `(0.55, 1.00, 0.50)` | |
| Section header ("BLASTER") | White `(1, 1, 1)` | |
| Status indicator ("ACTIVE") | Weapon green `(0.55, 1.00, 0.50)` | |
| BOUNTY label | Bounty gold `(1.00, 0.86, 0.42)` | `UiTheme.COLOR_BOUNTY` |
| Bounty counter | Bounty gold `(1.00, 0.86, 0.42)` | `UiTheme.COLOR_BOUNTY` |

---

## Divergences to Unify

The following near-duplicate gold values exist in the codebase and should be consolidated to `UiTheme.COLOR_BOUNTY`:

| File | Current value | Should be |
|---|---|---|
| `sector_map_v3.gd:207` | `(1.0, 0.92, 0.55)` | `UiTheme.COLOR_BOUNTY` |
| `sector_map_v3.gd:1911` | `(1.0, 0.85, 0.30)` | `UiTheme.COLOR_BOUNTY` |
| `sector_map_v3.gd:2048` | `(0.95, 0.92, 0.55)` | `UiTheme.COLOR_BOUNTY` |
| `scenes/cleared_summary.tscn:61` | `(1, 0.85, 0.45)` | `UiTheme.COLOR_BOUNTY` |
| `scripts/ui.gd:577` | `(1.0, 0.85, 0.3)` | `UiTheme.COLOR_BOUNTY` |

Similarly, these near-duplicate greens should consolidate to the sector-map `COLOR_NODE_GREEN = (0.55, 1.0, 0.50)`:

| File | Current value | Should be |
|---|---|---|
| `sector_map_v3.gd:102` (PROGRESS_COLOR) | `(0.40, 0.95, 0.40)` | Intentionally distinct — progress arc; keep |
| `sector_map_v3.gd:912` (boss defeated) | `(0.50, 1.0, 0.60)` | Align to `COLOR_NODE_GREEN` |
| `main_menu.gd:118, 181` | `(0.55, 1.0, 0.60)` | Align to `COLOR_NODE_GREEN` |

---

## Font

| Use case | Face | Size |
|---|---|---|
| HUD labels (pips, bounty, weapons) | `PixelOperator.ttf` | 7 pt |
| In-game captions | `PixelOperator.ttf` | 10 pt (`FONT_SIZE_CAPTION`) |
| Body text | `PixelOperator.ttf` | 12 pt (`FONT_SIZE_BODY`) |
| Buttons | `PixelOperator.ttf` | 14 pt (`FONT_SIZE_BUTTON`) |
| Headers | `PixelOperator.ttf` | 16 pt (`FONT_SIZE_HEADER`) |
| Titles | `PixelOperator.ttf` | 28 pt (`FONT_SIZE_TITLE`) |

Alternative face `PixelifySans.ttf` is available as a user-preference swap (Options menu). Both live in `res://graphics/fonts/`.
