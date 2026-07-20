# Planet Flyover Combat Backdrop — design contract (2026-07-18)

Status: IMPLEMENTATION CONTRACT — agents implement against this; deviations need sign-off.

## Goal

When a combat level sits on a PLANET poi (`Run.current_stellar.obj_kind == 0`), there is a
deterministic per-node chance the fight happens *close to the planet*: the standard space
parallax stack is skipped and replaced by the Planet Flyover backdrop (ground + atmosphere +
cloud layers, from the Planet Flyover Lab), matching the sector-map planet's type and color
identity. Day/night variants; night darkens the world via CanvasModulate with a lab-tunable
amount. The loading screen flying to such a level uses a matching flyover backdrop instead of
the space starfield. Gameplay is otherwise unchanged.

## Module layout

1. `scripts/parallax/flyover_backdrop.gd` (`class_name FlyoverBackdrop`, extends Control) —
   the extracted, UI-free world builder from `scripts/dev/planet_flyover_lab.gd`:
   ground ColorRect (`graphics/planet_ground.gdshader`), 3 atmosphere slices, 3 cloud layers
   (nebula2 / cloud_layer styles), the 3 shadow-mask SubViewports + caster registry, scroll
   accumulators (ground wrap 8×loop, cloud wrap 2×loop — do not change wrap rules).
   - API: `apply_settings(d: Dictionary)` (schema below), `register_caster(node, tex) /
     unregister_caster(node)`, `set_night(on, darkness, color)`, `track_combat_casters := false`
     (when true, polls "player" + "enemies" groups periodically and auto-registers casters —
     mirror `scripts/parallax/asteroid_shadow_rig.gd`'s tracking approach).
   - Owns an optional `CanvasModulate` for night (`Color.WHITE.lerp(night_color, night_darkness)`).
     In combat this darkens the whole world canvas (intended — HUD/Glass/Outline are separate
     CanvasLayers and stay lit).
   - Host-agnostic: builds 480×270 rects positioned by a `base_z: int` export so hosts control
     canvas ordering. Interleave order is fixed: ground < atmo0 < Far < atmo1 < Mid < atmo2 < Near
     (offsets 0,4,8,12,16,20,24 from base_z). Shadow-mask SubViewports are children of the
     component itself (never inside a play SubViewport).
   - PRESETS table, CLOUD_CFG, shadow consts move here wholesale from the lab.

2. `scripts/parallax/flyover_planner.gd` (`FlyoverPlanner`, static funcs, preload-const style,
   NO class_name — matches `Factions`/`LevelLauncher` convention) — the single source of truth
   for "is this node a flyover level and what does it look like":
   - `plan(stellar: Dictionary, run_seed: int, node_id: String) -> Dictionary` — returns `{}`
     (not a flyover) or the full settings dict. MUST be pure/deterministic: same inputs → same
     dict. Never writes Run. Called by both `backdrop_coordinator` and `loading_screen`.
   - Eligibility: `stellar.get("obj_kind", -1) == 0` AND `planet_type` maps to a preset
     (see table) AND flyover roll passes.
   - Rolls use decorrelated RNG: `rng.seed = abs(run_seed ^ hash(node_id)) ^ 0x464C594F` ("FLYO").
     Chance consts: `FLYOVER_CHANCE := 0.4`, `NIGHT_CHANCE := 0.35`.
   - Dev override: `Run.get_meta("forced_flyover")` — Dictionary merged over the planned dict,
     or `{"force": true}` to bypass the chance roll; `{"deny": true}` to force space backdrop.
     (Planner may read Run meta; it must not write.)

3. Consumers:
   - `scripts/parallax/backdrop_coordinator.gd::_populate` — new early branch: if
     `FlyoverPlanner.plan(...)` is non-empty, build a FlyoverBackdrop child with those settings
     (+ `track_combat_casters = true`) and SKIP the entire standard stack (planet/system/stars/
     asteroids/nebula/warp streaks/minefield decor). `stellar_override` beats Run as today.
     Flyover is OPT-IN via `@export allow_flyover := false` — only combat's main.tscn Backdrop
     instance sets it true (Roman 2026-07-18: the main screen / every other coordinator host —
     menu_backdrop, signal_event, labs, capture tools — keeps the space parallax unconditionally,
     even when Run carries mid-run node state).
   - `scripts/screens/loading_screen.gd` — flyover variant of the backdrop (see §Loading screen).
   - `scripts/dev/planet_flyover_lab.gd` — refactored to HOST FlyoverBackdrop (demo ships,
     recycle choreography, UI stay in the lab; world-building code moves out). Night knobs added.

## Settings dict schema (planner output = FlyoverBackdrop.apply_settings input)

```
{
  "flyover": true,
  "preset": int,                # index into FlyoverBackdrop.PRESET_NAMES
  "surface_type": int,          # shader generator (0..5)
  "colors": Array[Color] (8),   # preset palette after deterministic hue roll
  "emissive": float,
  "seed": int,                  # ground shader seed = stellar.planet_seed (terrain layout parity)
  "flight": float, "feature_scale": float, "loop_size": int, "octaves": int, "pixels": float,
  "relief": float, "river_cutoff": float,
  "atmo": bool, "atmo_color": Color, "atmo_opacity": float,
  "cloud_opacity": float, "cloud_coverage": float,
  "cloud_on": {"Far": bool, "Mid": bool, "Near": bool},
  "layer_style": {"Far": int, "Mid": int, "Near": int},      # 0=Nebula 1=Clouds
  "layer_opacity": {"Far": float, "Mid": float, "Near": float},
  "layer_color": {"Far": Color, "Mid": Color, "Near": Color},
  "ship_shadow": float,
  "night": bool, "night_darkness": float, "night_color": Color,
}
```

## Planet type → preset mapping (V3 `planet_type` ints, per stellar_gameplay.gd)

| V3 type | Planet | Flyover preset | Notes |
|---|---|---|---|
| 0 | LavaWorld | Lava | emissive kept |
| 1 | DryTerran | **Desert 2** | per Roman: desert planets use desert2 |
| 2 | NoAtmosphere | **Moonsteroid** | per Roman: moon planets use moonsteroid |
| 3 | LandMasses | Terran | |
| 4 | GasPlanet | — INELIGIBLE | no surface to fly over |
| 5 | IceWorld | Ice | |
| 6 | GasPlanetLayers | — INELIGIBLE | |
| 7 | Rivers | Terran | river_cutoff jitter range biased UP (+0.10..+0.25) |

## Base settings + jitter

Base = baked `DEFAULTS` dict in FlyoverPlanner mirroring the 2026-07-18 saved tuner values
(flight 0.35, feature_scale 8.0, loop_size 32, octaves 5, pixels 480.0, relief 0.35,
river_cutoff 0.5, cloud_opacity 0.6, cloud_coverage 0.55, atmo_opacity 0.18, layer defaults
per lab), OVERLAID with `user://tuners/planet_flyover.json` when present (dev machines: lab
tuning drives production — same load_all pattern as AsteroidStrongholds). Per-preset fields
(surface_type, colors, emissive, atmo, atmo_color) come from the preset, not the tuner.

Per-node jitter (deterministic, from the planner rng), clamped:
- `feature_scale ×= [0.8, 1.25]`
- `relief ×= [0.75, 1.3]`
- `river_cutoff += [-0.12, +0.12]` clamp [0.05, 0.95] (Rivers planet: [+0.10, +0.25])
- `cloud_opacity += [-0.15, +0.10]` clamp [0, 1]
- `cloud_coverage += [-0.12, +0.12]` clamp [0.1, 0.9]
- `flight ×= [0.85, 1.2]`
- FIXED (never jittered): loop_size, octaves, pixels.
- Color identity: ONE shared hue rotation of the preset palette, ±0.15 turn, rolled from
  `planet_seed` (reuse the lab's Randomize-Look `_shift_color` mechanism — shared rotation
  keeps ramps coherent). atmo/layer colors get the same rotation.

These ranges are v1 placeholders — Roman playtests, then tunes.

## Night

- `night_darkness` (default 0.45, range 0..0.8) and `night_color` (default #405088-ish) are
  LAB KNOBS: persisted in `user://tuners/planet_flyover.json`, emitted by Copy GDScript, with a
  Day/Night preview toggle in the lab. Production reads them via the planner's tuner overlay.
- Effect = CanvasModulate `Color.WHITE.lerp(night_color, night_darkness)`. Combat: whole world
  canvas (HUD unaffected — separate CanvasLayers). Loading screen: inside the backdrop
  CanvasLayer only (ship + title stay lit).

## Combat wiring

- Coordinator flyover branch as in §Module layout. Flyover z-band sits below all gameplay:
  ships 0, rocks -1, ground plane -5..-4 — set `base_z` so Near cloud tops out ≤ -8.
  (Wreck/recycle-under-Near-cloud choreography from the lab is DEFERRED — v1 keeps all flyover
  layers under gameplay.)
- Mutual exclusion for free: stronghold/asteroid-pepper POIs have `obj_kind != 0`; flyover
  requires `== 0`. Music, waves, director: untouched.
- Cloud shadows: `track_combat_casters = true` → player + enemies cast onto cloud layers.

## Loading screen

- `loading_screen.gd`: after `_resolve_identity`, compute
  `_flyover_plan = FlyoverPlanner.plan(Run.current_stellar, run.run_seed, run.current_node_id)`
  (guarded: empty/no Run → space). Optional `stellar_override: Dictionary` export consumed
  instead of Run for the lab.
- If flyover: SKIP `_build_stars()` + `rebuild_streaks()`; build a `CanvasLayer` at layer -10
  holding a FlyoverBackdrop (480×270 rects, CanvasLayer scale ×4 — same pattern as the stars
  layer; ColorRect shaders rasterize at physical res so this stays crisp, the SubViewport blur
  gotcha does not apply). Ship registered as the single shadow caster. Night modulate inside
  that CanvasLayer.
- Constraints from existing tests (must stay green):
  `tools/test_loading_readonly.gd` (no Run writes — planner is read-only),
  `tools/test_loading_hull_parity.gd` (ship stays direct child of World; no new World children
  exposing `hull`/`max_hull`), `tools/test_loading_launcher.gd` (credits.tscn target → empty
  stellar → space variant path must not error).
- Loading Screen Lab: "Destination" dropdown (Space / one entry per eligible planet type) that
  sets `stellar_override` + a Night toggle, and rebuilds. Knobs join Copy GDScript.

## Lab refactor guardrails

- `tools/test_flyover_clouds.gd` must still pass (update node paths if the component nests
  them, do NOT weaken assertions). Lab keeps: UI, presets dropdown, demo ship/enemies +
  recycle choreography (registered as casters via the new public API), Copy GDScript, JSON
  persist. Lab gains: Day/Night toggle + night_darkness slider + night_color picker.
- Lab preview contract applies (make_play_subviewport already used; keep verify guard if present).

## Verification

- `tools/parse_check.ps1` clean; `tools/test_flyover_clouds.gd`; the 3 loading tests.
- New `tools/test_flyover_combat.gd`: headless boot main.tscn with real Run autoload seeded
  (planet-POI stellar + `forced_flyover` meta) → assert FlyoverBackdrop exists, standard
  planet/star layers absent, night CanvasModulate present when forced night. Use the
  real-autoload pattern (`root.get_node("Run")` — a fake node named Run gets auto-renamed).
- New `tools/test_flyover_planner.gd`: determinism (same inputs → identical dict), eligibility
  table (gas planets never, obj_kind!=0 never), jitter stays in clamps over many seeds.
