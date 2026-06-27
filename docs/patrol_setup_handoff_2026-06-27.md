# Handoff: the shared hangar scene + dock cinematic substrate (for the patrol-setup work)

**Audience:** the agent building out the new Patrol Start sequence.
**TL;DR:** The hangar art/lights/markers, the cinematic substrate, the clutter system, the engine-light
feel, and a light-derived shadow prototype are **already built and SHARED** with the outpost dock. Patrol
already instances all of it. **Build on `scripts/dev/patrol_start.gd` — do NOT rebuild the hangar, the
runway lights, the point-light factory, the clutter, or the cinematic plate animation.** This doc maps
what exists so you don't redo it.

---

## 1. The shared authorable scene: `scenes/hangar_stage.tscn` (script `scripts/screens/hangar_stage.gd`)

ONE scene used by BOTH the outpost dock (`scripts/screens/outpost_arrival.gd`) and patrol
(`scripts/dev/patrol_start.gd`). Edit it in the Godot editor — it's authorable. Contains:

- **`Plate`** (Sprite2D, `outpost_background.png`, z −8) — the bay backdrop. The whole node is CENTRED on
  its origin; the screens DESCEND/SLIDE the node to animate fly-in/out.
- **`CanvasModulate`** (color ≈ 0.27) — the bay dim, **single source of truth**. `set_scene_dim(v)` /
  `scene_dim` writes it; the dev rails tune it. NOTE: a CanvasModulate dims its OWN canvas (plate/ships/
  clutter) but NOT a separate CanvasLayer — patrol's parallax backdrop is a separate upscaled element and
  is intentionally not dimmed by it.
- **`RunwayMarkers`** (12 `Marker2D`, M0–M11 down the centre) — at runtime `hangar_stage._build_runway()`
  drops a bright-amber ADDITIVE 2px square + an amber `PointLight2D` on each, and `_process` pulses them
  bottom→top. (KNOWN: the bottom 2–3 runway lights sit under the bottom UI bar in the dock; that's
  z-order/UI occlusion, not a bug — see §6.)
- **`FillLights`** (6 `PointLight2D`, a 2×3 grid, energy ~0.18) — the bay's ambient lights, fully authored
  in the .tscn (the script no longer touches their energy).
- **`Slots`** (`Marker2D`): `Pad`, `LifterIdle`, `Park0..Park6`, `FlankL`, `FlankR`. **Patrol reads these
  for ship-park positions** — `patrol_start._park_pos(i)` = `_hangar_off + hangar_stage.slot("Park%d")`.
  Author ship layout by moving these markers, NOT by hardcoding positions.
- **`ClutterZones`** (12 `Marker2D` along the walls) — where crate piles spawn (out of the way of
  ships/lifter/tractor by placement).

**`hangar_stage.gd` API you'll reuse (don't reinvent):**
`plate_size()`, `slot(name)`, `slots_prefixed(prefix)`, `set_scene_dim(v)`, `set_runway_speed(v)`,
`scatter_clutter(seed, amount=-1, make_shadows=true)`, `flank_pile(seed, per_side, make_shadows=true)`,
`clutter_node()`, `fill_lights()`, `ensure_key_light()`.

## 2. Shared effect modules (reuse, don't duplicate)

- **`scripts/effects/point_light_fx.gd`** — `make_texture(size)` (soft radial GradientTexture2D) +
  `make(pos, col, scale, tex)` (additive `PointLight2D`, energy 0, no shadow). The ONE point-light
  factory for the dock cinematics. Patrol's `_make_point_light` already wraps it.
- **`scripts/screens/hangar_clutter.gd`** — static crate scatterer. NON-OVERLAPPING flush packing,
  random 90° turn + h/v flip, three UNIFORM square sheets (`outpost_clutter_6px/7px_crates`,
  `outpost_clutter_8px_ammo_crates`; the old 16×16 sheets are retired). `populate(...)` for zone piles;
  `fill_trailer(trailer, seed)` drops a bed-fitting crate into the tractor trailer's `Body/TrailerArea`.
  All positions integer-snapped so they ride the plate without jitter. Patrol calls these in
  `_build_crates` / `_make_rig`.
- **`scripts/effects/light_shadow_fx.gd`** — see §4.

## 3. The cinematic substrate — patrol ALREADY has it (`scripts/dev/patrol_start.gd`)

Patrol instances the hangar stage (`_hangar_stage`, inside `_hangar` at `_hangar_off`), builds the
parked ships (each = body+livery via `ShipVisual.make_livery_material` + engine glow + markers + an
`EngineTrailFx` + a drop shadow), the lifter (`outpost_lifter.tscn` with grav/hover lights + a 4-frame
engine-glow anim), the dressing tractor+trailer rigs, the clutter, and a **tune rail** (Tab toggle,
sliders, "Copy GDScript", Replay). "Begin Patrol" spools the readied ship's engines and flies it up while
the bay slides down (mirrors the outpost depart). **All of this is done — extend it; don't recreate it.**

The dock/cinematic PATTERN (same in both screens): HD 1920×1080 `Control` composites a native 480×270
`SubViewport` (via `HdScreen.make_play_subviewport`) holding the bay; the HD menu Controls layer over it;
the plate descends/centres/slides to read as flying into/out of the hangar. Engine beats bracket the
MOTION not the state (lit through descent, cut after fully set down; spool BEFORE liftoff). Drop shadow =
a black silhouette of the body cell whose offset/scale/alpha tween (high vs landed).

## 4. Engine lights + shadows (recently reworked — know the state before you touch them)

- **Engine point lights** are FOCUSED at the nozzle markers (outpost SCALE 0.45 / patrol 0.3 on the
  shared light tex), bright (energy 1.8), fade in/out with the engine glow, and **flare** (×2.2 energy /
  ×1.7 size, EASE_IN) right as the ship accelerates out — in BOTH screens.
- **OPEN finding (don't re-chase):** the engine light "doesn't project onto the bay plate once the ship is
  over it" is **z-order occlusion** — the hull (z −2) is drawn OVER the plate (z −8) it lights, so only
  the spill beyond the hull shows. It is NOT a light-mask/Light-Mode bug (verified: no unshaded materials,
  masks all default-matching; `PointLightFx.make` already forces `range_item_cull_mask = 0xFFFFF`).
- **`scripts/effects/light_shadow_fx.gd` — light-derived shadow PROTOTYPE.** Projects black silhouettes of
  registered casters AWAY from registered lights (per-frame, pooled). Modes: LEGACY (baked drop shadows,
  the DEFAULT) / KEY (one central key light) / FILL (the 2×3 fill lights, multi-shadow); a "dynamic"
  toggle adds bright moving lights (engines/lifter/tractor) as casters; a per-caster `lift` fakes drop
  height. **Patrol already wires this with a rail toggle (`_apply_shadow_mode`, `_extra_casters`,
  `_dynamic_lights`).** It's UNREVIEWED and default-off — leave LEGACY unless Roman asks.

## 5. Interactions you should be aware of

- **The outpost dock is now PRODUCTION** (this session): the sector-map "Visit Outpost" button opens
  `outpost_arrival.tscn` (live `Run` shop wiring); `outpost.gd`/`outpost.tscn` are retired-but-on-disk.
  Because the hangar stage is SHARED, **any change you make to `hangar_stage.tscn` affects the live
  outpost too** — keep the Slots/markers the outpost reads intact, or coordinate.
- **Docking cinematic frequency** is now a Settings pref (`Settings.outpost_dock_anim`: always / once-per-
  boss / once-per-patrol / never) with a `begin_landed()` skip path on the dock. If patrol gets a real
  "fly in" entry later, consider the same gate (`_should_play_cinematic` is a good model in
  `outpost_arrival.gd`).
- **Scene-dim** is the CanvasModulate ONLY now (the old container-modulate path was removed from both
  screens). Use `hangar_stage.set_scene_dim()`.

## 6. Gotchas (hard-won)

- **HD scope:** the screen owns it when `manage_hd_scope=true` (standalone) and drops it on exit; the
  lab/embedded host sets it false and manages itself. Patrol uses `HdScreen.enter`/`make_play_subviewport`.
- **Autoloads (`Run`/`Settings`) are NOT loaded in `-s` SceneTree headless** — instantiate them manually
  in any driver (see `tools/test_outpost_live.gd` for the pattern).
- **Sub-pixel jitter:** child sprites at fractional local offsets shimmer against the moving plate — keep
  positions integer-snapped (the clutter already does).
- **UI bars overlap the bay edges:** the top money bar (native y 0–37) and bottom action bar (y 232–270)
  cover the runway ends in the dock. Patrol's UI differs, but watch for the same occlusion.
- **Verify with `tools/parse_check.ps1`** (uses the `_console.exe` for stdout) — RID/ObjectDB "leaked at
  exit" lines are headless dummy-renderer noise, not errors.

## 7. The short "don't redo" list
Hangar art + lights + markers · runway pulse · the point-light factory · the clutter/crate system · the
plate fly-in/out animation · the engine-beat timing · the drop-shadow height model · the light-derived
shadow prototype · the tune-rail + Copy-GDScript pattern. **All shared and done.** Start from
`scripts/dev/patrol_start.gd` and the markers in `scenes/hangar_stage.tscn`.
