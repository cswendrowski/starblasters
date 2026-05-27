# Sector Map V3 — Label Style Reference

Single source of truth for every text element on the sector map screen.
When in doubt, this file wins over code comments.

---

## Coordinate system

Viewport is 480×270. All positions are in screen-space pixels (no camera).  
Scene markers in `scenes/sector_map_v3.tscn` define anchor points; this doc
describes what goes at each marker and how it should look.

---

## Label style defaults

Unless a row explicitly overrides a property, use these defaults:

| Property | Default |
|---|---|
| Font | `FONT` (preloaded pixel font) |
| Font size | **7** (matches star label) |
| Outline size | 1 px |
| Outline color | `Color(0, 0, 0, 1)` — opaque black |
| Background | `StyleBoxFlat` black — `Color(0, 0, 0, 0.85)`, 2 px L/R margin, 0 T/B |
| Alpha | **1.0** (fully opaque) |
| Z-index | **100** (on top of everything) |
| Mouse filter | `MOUSE_FILTER_IGNORE` |
| Centered | `HORIZONTAL_ALIGNMENT_CENTER`, `custom_minimum_size.x` set |

UI chrome (sector header, player status, buttons) is exempt from the black-bg
rule — those live outside the map content layer.

---

## Content labels (appear on the map itself)

### 1. Star name label
| Property | Value |
|---|---|
| Marker | `star_label_N` — child of `star_N`, offset `(0, -32)` from star center |
| Content | Generated star name, e.g. `"Gliese-892"` — from `_generate_celestial_name("star", seed)` |
| Font size | 7 |
| Color | `Color(0.75, 0.85, 1.0, 1.0)` — cool blue-white |
| Background | Black (default) |
| Alpha | 1.0 |
| Z-index | 100 |
| Notes | Centered on star anchor x; top of label at `star.y - 36` (centers visually at `star.y - 32`) |

---

### 2. POI body name label
| Property | Value |
|---|---|
| Marker | `row_N_label_M` — child of `row_N_poi_M`, offset `(0, -24)` from POI center |
| Content | Generated celestial body name, e.g. `"Rock-73-Delta"` — from `_generate_celestial_name(type, seed)` |
| Font size | 7 |
| Color | `Color(0.75, 0.85, 1.0, 1.0)` — cool blue-white |
| Background | Black (default) |
| Alpha | 1.0 |
| Z-index | 100 |
| Notes | Only drawn for uncompleted POIs. Top of label at `poi.y - 24`. Centered on `poi.x`. |

---

### 3. Boss label
| Property | Value |
|---|---|
| Marker | `boss_label_N` — child of `row_N_boss_N`, offset `(0, -24)` from boss center |
| Content | `"BOSS"` when unlocked/active; `"DEFEATED"` when completed |
| Font size | 7 |
| Color (active) | `Color(0.90, 0.30, 0.30, 1.0)` — medium red |
| Color (defeated) | `Color(0.50, 1.0, 0.60, 1.0)` — muted green |
| Background | Black (default) |
| Alpha | 1.0 |
| Z-index | 100 |
| Notes | Top of label at `boss.y - 24`. Centered on `boss.x`. Always visible (not hover-gated). |

---

### 4. Boss lock progress counter
| Property | Value |
|---|---|
| Position | `(boss.x, boss.y + 6)` — below the boss dot |
| Content | `"k/N"` — completed / total POIs in this row |
| Font size | 4 |
| Color | `Color(1.0, 0.85, 0.30, 1.0)` — gold |
| Background | None |
| Alpha | 1.0 |
| Z-index | 11 |
| Notes | Only shown when boss is locked (not yet unlocked, not defeated). Utility indicator only. |

---

## Node icons (not text, but hover-gated visuals)

### 5. POI node icon
| Property | Value |
|---|---|
| Position | `row_N_poi_M` — the POI center point |
| Source | `ICON_STRIP` AtlasTexture, region = `node_type * 32` |
| Scale | `(0.5, 0.5)` — 16×16 display |
| Color | `COLOR_NODE_GREEN = Color(0.55, 1.0, 0.50, 1.0)` |
| Rest alpha | 0.0 (uncompleted) / 0.6 (completed) |
| Hover alpha | 0.9 |
| Z-index | 5 |
| Notes | No text label drawn below the icon. Node type shown only in the selected-node panel (see UI chrome below). |

---

## UI chrome (exempt from black-bg / z-100 defaults)

### 6. Sector header
| Property | Value |
|---|---|
| Marker | `sector_label` at `(256, 16)` |
| Content | `"<SectorName>  —  Sector N / N"` |
| Font size | 9 |
| Color | `Color(0.85, 0.92, 1.0, 0.95)` |
| Background | None |
| Alpha | 1.0 |
| Alignment | Centered across full 480-px width |

---

### 7. Player status
| Property | Value |
|---|---|
| Marker | `player_status` at `(64, 232)` |
| Content | Hull / Shield / Bounty bits (same as Manage Ship modal) |
| Font size | 9 |
| Color | `Color(0.85, 0.92, 1.0, 0.95)` |
| Background | None |

---

### 8. Selected node label
| Property | Value |
|---|---|
| Marker | `selected_node_label` at `(256, 232)` |
| Content | `"<mission name> at <body name>"` — e.g. `"Alpha Intercept at Rock-73-Delta"` |
| Font size | 9 |
| Color | `COLOR_NODE_GREEN = Color(0.55, 1.0, 0.50, 1.0)` |
| Background | None |
| Alpha | 0.0 at rest; 1.0 when a node is selected |
| Notes | Mission name from `_generate_poi_name`; body name from `_generate_celestial_name`. For bosses: `"BOSS ENCOUNTER at <star name>"`. |

---

### 9. Buttons (MANAGE SHIP / DEPART / OPTIONS)
| Button | Marker | Position | Notes |
|---|---|---|---|
| MANAGE SHIP | `manage_ship_button` at `(64, 256)` | `(26, 248)` | Opens manage-ship modal |
| DEPART | `depart_button` at `(256, 256)` | `(228, 248)` | Alpha 0.3 until selection; 1.0 when active |
| OPTIONS | `options_button` at `(448, 256)` | `(420, 248)` | Opens options overlay (same as Esc) |

Buttons live on `BottomBtnLayer` (CanvasLayer 6). Font size 9.

---

## What to remove

These label types exist in current code but are **not part of the design**:

- `_spawn_poi_name_label` — mission name drawn below POI body. **Remove.** Mission name now belongs only in the selected-node panel.
- `_add_hover_label_icon` text showing `"b"` / `"Asteroid"` / `"Belt"` — type hint drawn above POI. **Replace** with the POI body name label (item 2 above).
- Any label with `label_rest < 1.0` for content labels (hover-fade of text is gone; icons still hover-fade).
