# Sector Map — HD UI Overlay Scope (2026-06-02)

## Goal

Bring the sector map's interactive UI to HD (1920×1080) while keeping its
celestial art at the chunky native-upscaled look, WITHOUT breaking the existing
runtime marker-driven placement. Prototype in a dev sandbox first
(`scenes/dev/sector_map_hd_lab.tscn`), then port the proven approach into the
live `sector_map_v3` once it looks right.

## Requirements (Roman)

1. Use the SubViewport setup (`HdScreen.add_upscaled_backdrop` pattern) so
   planets / stars / asteroids / routes / POI icons stay chunky in-game.
2. Retain the runtime `Marker2D`-driven scene building already in place — things
   stay placed where intended.
3. Options, Manage Ship, Depart, and the Escape menu render in HD, positioned
   from their markers.

## How the live sector map works today (the constraints)

- `scripts/sector_map_v3.gd` is a single **Node2D** (~2500 lines) rendered at the
  native 480×270 viewport (upscaled 4× by the canvas stretch).
- **Markers are the source of truth.** `scenes/sector_map_v3.tscn` holds
  `Marker2D` nodes (`sector_label`, `player_status`, `manage_ship_button`,
  `options_button`, `depart_button`, `star_N`, `star_label_N`, `boss_N`,
  `row_N_poi_M`, `row_N_label_M`, …). The code reads
  `(get_node(path) as Marker2D).global_position` to place celestial bodies,
  routes, POI icons, labels, and (for buttons) hardcoded offsets near those
  anchors. (See `docs/sectormap_labels.md`.)
- **Hit-testing** is in `_unhandled_input`: `get_local_mouse_position()` (480
  space) → `distance_to(hit.pos) <= hit.radius` against `_poi_hits` (POIs) and
  `_boss_entries` (radius 16). Selection sets `_selected_node_id`, lights the
  Depart button, and updates the selected-node label.
- **Buttons** (`MANAGE SHIP` / `OPTIONS` / `DEPART`) live on a `CanvasLayer`
  (`BottomBtnLayer`, layer 6) at fixed 480 positions; `OPTIONS`/Esc open the
  (already-HD) `OptionsOverlay`; `MANAGE SHIP` opens a modal built in-scene.

## Target architecture

```
SectorMapHd (root, Control, HD via HdScreen.enter)
├── SubViewport (480×270)            ← the chunky map, render_target ALWAYS
│    └── MapContent (Node2D)          ← all 480-space art: starfield _draw,
│         · Marker2D anchors            celestial scenes, routes, POI icons,
│         · celestial / routes / POIs   AND the name/status labels (text stays
│         · name + status labels        chunky, part of the "in-game" look)
│         · exposes _poi_hits / _boss_entries / selection API
│         · NO buttons, NO input handling, NO scene transitions
├── TextureRect (full HD, STRETCH_SCALE, nearest)  ← displays SubViewport ×4
└── HdOverlay (Control / CanvasLayer, 1920×1080)
     · MANAGE SHIP / DEPART / OPTIONS buttons at (marker × 4), UiTheme-styled
     · handles ALL input:
         - buttons → direct (HD Controls)
         - POI/boss click → mouse ÷ 4 → distance test vs MapContent._poi_hits
         - Esc → OptionsOverlay (HD)
     · MANAGE SHIP modal in HD; OptionsOverlay already HD
     · drives MapContent selection + reads it to light Depart
```

### Coordinate math (the crux)
- Markers live in MapContent at 480 coords. HD overlay element position =
  `marker.global_position * 4`.
- A click at HD mouse `m` selects via `m / 4` in 480 space, then the existing
  `distance_to(hit.pos) <= radius` test. (Scale factor = 1920/480 = 4, a clean
  integer — no rounding drift.)
- The SubViewport content never receives the outer click (it's isolated); the
  overlay owns hit-testing and calls into MapContent's selection.

### What stays chunky vs HD
- **Chunky (SubViewport):** stars, planets, asteroids, glitter, routes, POI
  icons, starfield, AND the name/status/sector/selected labels (pixel text is
  part of the in-game aesthetic; Roman's list of HD elements was the buttons +
  menus, not the labels). *Labels-to-HD is a cheap follow-up knob if wanted.*
- **HD (overlay):** the 3 buttons, the Manage Ship modal, the Options overlay,
  Esc handling.

## Dev sandbox (this pass) — `scenes/dev/sector_map_hd_lab.tscn`

Proves the architecture WITHOUT touching the live map:
- Instances the live `sector_map_v3.tscn` **into the SubViewport** (reuses all
  its art + marker + POI logic verbatim). Its `_unhandled_input` never fires
  (SubViewport input disabled) so no accidental scene transitions.
- Hides the instance's `BottomBtnLayer` (its chunky buttons).
- Displays the SubViewport ×4 (nearest) full-screen.
- Builds HD buttons positioned at the instance's button markers × 4.
- POI clicks: HD mouse ÷ 4 → test against `inst._poi_hits` → call
  `inst._on_poi_selected(id)` (real chunky selection feedback) + light the HD
  Depart button.
- OPTIONS / Esc → `OptionsOverlay.open()` (already HD, full demo).
- MANAGE SHIP / DEPART → stubbed (toast) for now — the sandbox is for nailing
  the chunky-art + HD-button-placement + hit-test math; the HD modals come next.

This lets us tune button placement (marker × 4), confirm the chunky upscale, and
validate click mapping on a live, animated map — safely.

## Port-to-live plan (after the sandbox looks right)

The live `sector_map_v3` needs a separation so its art/markers/POI-data are
reusable while its UI/input move to an HD overlay. Options, cheapest first:
1. **Wrap-in-place:** give `sector_map_v3` an optional "embedded" mode (skip
   building buttons + skip `_unhandled_input` transitions) and host it in a
   SubViewport under a new HD host scene that owns the overlay. Least surgery to
   the 2500-line file; the host becomes the live `SECTOR_MAP_SCENE`.
2. **Extract MapContent:** split the Node2D's art/marker/POI code from its
   UI/input into a `MapContent` node reused by both. Cleaner, more work.

Recommendation: prototype with #1 (the sandbox already does this via external
hiding), then decide. `SectorMapRoute.SECTOR_MAP_SCENE` is the single switch to
flip when the HD host is ready.

## Refinement (2026-06-02b — after first lab look)

The first lab (whole map in the SubViewport) showed the **labels are unreadable**
— 7–9px PixelOperator upscaled 4× is mush. Roman's call (correct): the SubViewport
should hold only the **pixel objects**; *everything else renders in the HD overlay*.

Revised split:
- **SubViewport (chunky, stays):** `_draw()` content (dark fill + starfield dots +
  asteroid-pixel glitter — these are baked into `_draw`, can't be externally
  separated, and read fine as chunky background) + the instanced celestial bodies
  (planets / stars / asteroids — the genuine pixel-art).
- **HD overlay (pulled out, positioned at marker × 4):** ALL text labels, POI
  icons, boss nodes + rings, route lines, buttons, menus.

Why this is clean: routes (`Line2D`), icons (`Sprite2D`), labels (`Label`) are all
**nodes** in the instance — hideable externally; the HD overlay rebuilds them.
Hit-testing becomes HD-native (icons/bosses are HD elements at marker × 4 → click
them directly; no ÷4 mapping needed for those).

Asset note: **no SVGs exist** (only `icon.svg`). Sector icons are 32px PNG tiles
(`sector_icons.png` / `sector_nodes.png`) currently drawn at 0.5×/0.25× — render
them at full size in HD for crisp icons. Smooth vector icons would need new art.

Lab strategy — **read-and-rehost** (no edits to live `sector_map_v3`): instance it
in the SubViewport (it generates names/positions/types as usual), then walk it,
hide its `Label`/`Sprite2D`-icon/`Line2D`-route/boss nodes, and rebuild HD copies
in the overlay from their text/position × 4. Increment order: (1) **labels → HD**
[done], (2) icons → HD, (3) boss nodes + routes → HD, (4) HD-native hit-test.

## PORT HANDOFF BRIEF (next session — lab is locked & approved)

The dev lab `scenes/dev/sector_map_hd_lab.tscn` (+ `scripts/dev/sector_map_hd_lab.gd`)
is the **proven reference implementation** of the HD look (Roman-approved). The
port turns that approach into the live screen. Recommended path = **wrap-in-place**.

Steps:
1. **New live host** (e.g. `scenes/sector_map_hd.tscn` + script), modeled on the
   lab: `HdScreen.enter`, a 480×270 SubViewport containing the instanced map,
   TextureRect upscale ×4, HD overlay. Reuse the lab's read-and-rehost verbatim:
   labels→HD (HEADER sector title / BODY rest), icons→HD hi-res glyphs
   (`HIRES_GLYPHS`, EXPAND_IGNORE_SIZE), boss dots+rings→HD (sized via
   BOSS_DOT_PX/BOSS_ICON_PX/BOSS_RING_RADIUS), hover lerp in `_process`. ROUTES
   stay in the SubViewport (behind planets — do NOT rehost).
2. **Embedded mode on `sector_map_v3`**: add a flag so when embedded it skips
   building its own bottom buttons AND skips `_unhandled_input` transitions
   (the host owns input). Also set the SubViewport's bg instead of the global
   `RenderingServer.set_default_clear_color`. Guard `_ready` side-effects
   (save_to_disk / hull regen / advance_if_complete / music) so they run ONCE —
   either keep them in the embedded map (host doesn't duplicate) or move to host.
3. **Real interactions** (lab stubs these): POI/boss click → call the embedded
   map's `_on_poi_selected`/`_on_boss_selected` (already done in lab) AND drive
   the selected-node label (hidden chunky one → update an HD copy, or re-show).
   **DEPART** must call the real transition (`sector_map_v3._on_depart_pressed`
   logic / SceneTransition to combat/outpost/signal/hazard by node type).
   OPTIONS/Esc → OptionsOverlay (HD, done). MANAGE SHIP → `manage_ship.tscn`
   (set Run meta `manage_ship_return` to the sector map scene first).
4. **Remove the old in-map Manage Ship modal** + its helpers from `sector_map_v3`
   (the new `manage_ship.tscn` replaces it). The no-bounty modal is already
   native-pinned; either keep it or rebuild HD in the host.
5. **Flip the route**: `SectorMapRoute.SECTOR_MAP_SCENE` → the new host scene.
   Re-test the full loop: main menu → onboarding → map → combat → cleared → map
   → outpost → map → boss. Add the host to `tools/parse_check.ps1`.
6. Pre-existing `sector_map_v3` "bool+float" console error fires live too — not
   from the port; optionally fix separately (out of scope).

## Risks / watch-items
- **Input isolation:** the SubViewport must not eat or transition on clicks
  (`gui_disable_input = true`); all input handled by the overlay.
- **Animation cost:** SubViewport `UPDATE_ALWAYS` re-renders the animated map
  every frame — same work as today, just into a texture. Watch perf with many
  glows/asteroids.
- **Selected-label + Depart state** must stay in sync between MapContent
  (selection source) and the HD overlay (Depart enable). Keep one owner.
- **Manage Ship / boss modals** currently build in-scene (480). Porting them to
  HD means rebuilding via `UiTheme.make_modal` in the overlay.
- **Clear color:** `sector_map_v3._ready` calls
  `RenderingServer.set_default_clear_color` globally — when embedded, set the
  SubViewport's own bg instead so it doesn't tint the whole window.
```
