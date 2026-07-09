# Parallax V4 Showcase — build plan (2026-07-06)

> **STATUS: WP1-7 ALL BUILT (WP1/2 2026-07-06, WP3/4 Phase-2 + WP5/6/7 feedback-round
> 2026-07-08), verified headless, UNCOMMITTED, awaiting Roman's in-editor drive.**
> WP5-7 as-built notes: **jitter root cause** — combat renders 1080p (`canvas_items` stretch)
> and the 480-grid steppiness comes from `snap_2d_transforms_to_pixel=true`; layer offsets were
> already floats. `layer_base.pixel_snap=false` (viewport-wide) genuinely smooths production;
> the lab demos it via an **HD raster** toggle (`SubViewport.size 1920×1080 +
> size_2d_override 480×270 + override_stretch` — engine-native, no content scaling; default
> ON = combat-accurate). Lab owns the snap-TRUE direction (`_apply_viewport_snap`); the
> layer setter only forces FALSE (inert contract). `asteroid_layer_mult (2,1,0.7)` → 8/5/2
> from 4/5/3 bases. Composer `star_mode`: distant_star 60% (scale 0.06-0.14, glow_boost 1.8 +
> bloom halo) / near_star 40% (0.75-1.2, planets 0.05-0.30); single-planet size_scale
> 0.55-1.7. `body_parallax` depth: `1 + clamp(size/240,0,1.5) × mode_factor` (near 1.0 /
> distant 0.15 / default 0.5); bodies register at SPAWN (respawn-class knob); known benign
> overlap: lateral_wander owns the main planet's X over body_parallax. WP6: lab
> WorldEnvironment = combat's env + `use_hdr_2d` on the SubViewport (hand-built SubViewports
> don't inherit the project HDR flag — nothing ever bloomed in labs); Bloom toggle flips both.
> Panel-stretch culprit was non-autowrapping CheckButton labels driving min-width through a
> no-horizontal-scroll ScrollContainer — fixed PANEL_W=460 + autowrap, regression-asserted.
> Ship sprite: hframes=3/frame=1 (ShipVisual too heavy for a lab prop). Phase 2 as-built notes: composer fallback +
> palette live behind `use_composer_fallback` / `use_palette` (+ `forced_kind`); coordinator
> exposes `palette` {key,accent,dust,deep} + `last_stellar` for the lab; **accent falls back to
> `key` in system mode** (sampler returns WHITE there — a WHITE accent would un-grade the scene;
> reviewer fix). Reviewer also fixed a pre-existing ordering bug: on regenerate, layer_streaks
> respawned during `_clear_spawned` BEFORE `_populate` wrote its config, so streak config (incl.
> palette tint) landed one generation late — `layer_streaks.rebuild()` (change-aware, no-op when
> config unchanged) is now called after the coordinator's streak writes and the lab's
> `_reassert_post_regen`. Lab: COMPOSITION section (kind picker + rolled-composition status
> line; `force_asteroids` removed — the composer decides rocks, force kind=Asteroid to tune
> sizes) + PALETTE section (master toggle + 4 live swatches; per-consumer matrix deliberately
> NOT built — streaks' own tint toggle is the one override, and it wins over the master). The
> lab test now moves Roman's persisted JSON aside and forces sections on (was
> toggle-state-sensitive). Still deferred: recycle-ghost retint (combat integration),
> sector-map nebula-table dedup, `menu_backdrop` composer flip (one line, ship when approved). Launch via dev menu → "[ Parallax Showcase ]". As-built deviations from
> this plan (all reviewed + accepted): the V1 dominant-color sampler actually lives at
> `_sample_blackhole_disc_color` (not `:270-289`) and its output is SDR-normalized before use
> as a grade (HDR kit palettes would brighten instead of tint); the starfield reseed derives
> from `seed_val ^ salt` instead of `rng.randi()` (consuming the main stream would have
> shifted the fallback planet pick = a production visual change); the coordinator caches
> authored asteroid counts so `regenerate()` doesn't compound density scaling; streak
> alpha/tint are respawn-applied (the particle gradient is built at spawn), so
> `streak_alpha` is in the lab's `RESPAWN_KEYS`. Tests:
> `tools/test_parallax_showcase_api.gd` + `tools/test_parallax_showcase_lab.gd` (both
> VERDICT: PASS). Star FAR/NEAR rates stay consts in `layer_stars.gd` — the lab shows the
> sliders but ships those two via the Copy block as hand edits.

Companion to [`parallax_backdrop_review_2026-07-06.md`](parallax_backdrop_review_2026-07-06.md).
Goal: a dev lab that demonstrates the review's proposed visual fixes **live and A/B-toggleable**,
so Roman can judge each change against the current look and export the winners.

**Core principle:** the proposed behaviors are implemented in the PRODUCTION parallax scripts as
opt-in exports with **inert defaults** (default = today's exact visuals). The showcase lab is a
thin driver over those knobs. Consequences:
- Zero production visual change until a knob is turned (safe to merge any time).
- The showcase exercises the exact code that later ships — no lab-only reimplementation drift
  (the mistake that left Nebula Lab's exports with no landing site).
- Copy GDScript emits values whose destinations actually exist.

Two work packages, sequential (WP2 builds against WP1's API):

---

## WP1 — engine capabilities + enabling fixes (scripts/parallax/*)

### 1a. Enabling bug fixes (from review §3 — required for the lab to function)

1. **Seed override / regenerate.** `backdrop_coordinator.gd`: new
   `func regenerate(seed_override: int = -1) -> void` — tears down spawned content and re-runs
   `_populate` with `seed_override` when >= 0 (store `_seed_override`; `_populate`'s rng uses it
   over the run-derived seed). This unblocks "Generate New" (review P1: the time-based branch at
   `:98-109` is dead because `Run` is an autoload). Keep the run-derived path as default.
2. **Global-RNG restore (P0).** `layer_planet.gd:100` and `:159`: after the `seed(planet_seed)` +
   `randomize_colors()` pair, restore global RNG state (save `randi()` from a local RNG before, or
   simplest: call `randomize()` after — decision: use capture/restore via
   `var _s := randi()` … `seed(_s)` pattern with a comment; `randomize()` acceptable fallback).
3. **Moons material duplication (P1).** `attach_moons` (`layer_planet.gd:427-497`): call
   `_duplicate_materials(moon)` before `set_seed` — mirrors the other three spawn sites.
4. **Starfield reseed (P2).** `backdrop_coordinator._populate`: call the stars layer's
   `reseed(rng.randi())` so the star layout varies per level (method exists,
   `layer_stars.gd:42-48`).

### 1b. New capability knobs (all inert by default)

| Knob | Where | Default (=today) | Behavior when set |
|---|---|---|---|
| `lateral_strength: float` | `backdrop_coordinator.gd` export | `0.0` | See lateral-parallax spec below |
| `set_lateral_input(norm_x: float)` | coordinator method | — | −1..1 from playfield center; coordinator smooths (`lerp` factor ~0.1/frame) into `_lateral_pos` |
| `apply_lateral(px: float)` | `layer_base.gd` virtual | sets `offset.x = px * scroll_rate` | `layer_stars.gd` overrides: applies to the two Parallax2D children's `scroll_offset.x` scaled by FAR_RATE/NEAR_RATE ×(some gain, they're tiny — use ×4 like the vertical rates' relative feel; agent judgement, must visibly differ per sub-layer) |
| `drift_variance: float` | `layer_stellar.gd` export | `0.0` | each rock gets persistent per-instance `vx = rng ±drift_variance` px/s (scaled by the layer's scroll_rate so far rocks drift less); applied in `_process`; X-wrap at screen edge + margin like Y wrap |
| `lateral_wander: float` | `layer_planet.gd` export | `0.0` | planet body drifts sinusoidally ±`lateral_wander` px around spawn X, period ~40s |
| `streak_alpha: float` | `layer_streaks.gd` export (promote hardcoded 0.6) | `0.6` | drives the streak color alpha |
| `streak_speed_variance_min: float` | `layer_streaks.gd` export (promote hardcoded 0.8) | `0.8` | lower bound of the per-streak speed multiplier (upper stays 1.2) |
| `streak_tint: Color` | `layer_streaks.gd` export | `Color.WHITE` | multiplies streak color (palette tinting) |
| `use_dominant_grade: bool` | `backdrop_coordinator.gd` export | `false` | `_apply_tints` + composite grade use `layer_planet.get_dominant_color()` instead of `PLANET_TINT` |
| `get_dominant_color() -> Color` | `layer_planet.gd` method | — | port of V1's brightest-color sampler (`galaxy_backdrop.gd:270-289`) run against the live planet's post-randomize palette (`get_colors()` on the kit); cache per spawn; fallback `PLANET_TINT` color if unavailable |

**Lateral-parallax spec:** each frame the coordinator computes
`_lateral_pos = lerpf(_lateral_pos, _lateral_target, 0.1)` and calls
`layer.apply_lateral(-_lateral_pos * lateral_strength)` for every layer. With
`lateral_strength = 0` this is a no-op (skip the loop entirely when 0 to keep the hot path
clean). `lateral_strength` is "px of near-layer shift at full strafe" — because
`apply_lateral` multiplies by `scroll_rate`, depth falloff is automatic. Stellar wrap logic
only checks Y (`layer_stellar.gd:293`) so X offsets are safe; verify nebula stays screen-fixed
(its counter-offset is Y-only — the nebula ColorRect must also counter X, or be exempted;
agent must handle this explicitly).

**Already-existing knobs the lab will drive (no WP1 work):** per-layer `scroll_rate` /
`brightness` / `contrast` / `modulate_color` (`layer_base.gd` exports), `drift_speed`,
`warp_streak_speed` / `warp_streak_count`, `nebula_swirl` (coordinator exports), per-layer
`asteroid_count` / `asteroid_size_min/max` / `asteroid_size_pow` / `nebula_enabled` /
`nebula_alpha` (`layer_stellar.gd` exports — verify exact names before wiring).

### 1c. Verification for WP1
- `tools/parse_check.ps1` passes.
- Headless boot of `scenes/main.tscn` (smoke) — no errors, no visual-change expectation.
- A tiny headless script `tools/test_parallax_showcase_api.gd` that instances
  `backdrop_coordinator.tscn`, calls `regenerate(12345)` twice and asserts the planet index /
  rock positions are identical (determinism), calls `regenerate(999)` and asserts they differ,
  calls `set_lateral_input(1.0)` + ticks and asserts layer `offset.x` moved only when
  `lateral_strength > 0`, and asserts `get_dominant_color()` returns a non-white color for a
  seeded planet.

---

## WP2 — the showcase lab (scenes/dev/parallax_showcase.tscn + scripts/dev/parallax_showcase.gd)

A new lab, NOT an extension of the existing `parallax_tuner.gd` (which stays the
fine-grained per-layer editor). The showcase is opinionated: it exists to A/B the review's
proposal.

### Layout
Follow the established lab pattern (`nebula_lab.gd` / `parallax_tuner.gd`): backdrop instance
at combat scale on the left (**`drift_speed = 50`, the combat-live value** — review flagged
that tuning at 22 was a trap), scrollable control panel on the right, Esc to close,
single-instance, registered in `dev_menu.gd` as **"Parallax Showcase"**.

### Controls (top to bottom)

1. **Preset row:** `[ CURRENT ]` `[ PROPOSED ]` buttons — each applies a full named constant
   set (below). A third `⟲ Generate New` button calls `regenerate(randi())` (works now thanks
   to WP1). A planet-type OptionButton (reuse `PLANET_TYPE_NAMES` list from parallax_tuner)
   forcing the planet for consistent comparison.
2. **Per-feature toggle sections** — each review fix is its own CheckButton + its sliders, so
   Roman can mix (e.g. proposed ratios + current brightness):
   - **Scroll ratios** — 6 sliders (stars far/near, planet, far/mid/near) + drift_speed.
   - **Brightness ramp** — brightness far/mid/near + contrast far/mid.
   - **Rock sizes** — near min/max + size_pow (rebuild rocks on change via `regenerate`
     with the same seed, so only the sizes change).
   - **Palette grade** — `use_dominant_grade` toggle + tint-strength slider(s); show a swatch
     of `get_dominant_color()`.
   - **Lateral parallax** — `lateral_strength` slider + strafe input: a small ship sprite at
     the bottom of the playfield band driven by ←/→ (feeds `set_lateral_input` from its
     playfield-normalized X), plus an "auto-sweep" CheckButton (sine, ~4s period) for
     hands-free judging.
   - **Rock drift** — `drift_variance` slider; planet `lateral_wander` slider.
   - **Streaks** — speed (with a 480 px/s marker/clamp toggle), alpha, count,
     variance-min, palette-tint toggle (tint = dominant color).
   - **Nebula** — per-layer alpha sliders preset-loaded with current (0.1/0.2/0.15) vs
     proposed monotonic (0.08/0.14/0.2).
3. **Persistence:** save/load `user://tuners/parallax_showcase.json` (auto-load on open,
   auto-save on close, like the other labs).
4. **Copy GDScript** (tuner contract — mandatory): emits a paste-ready block **grouped by real
   destination**, e.g.:
   ```
   # backdrop_coordinator.tscn overrides:
   #   LayerStellarFar: scroll_rate=0.18 brightness=0.35 contrast=0.5
   #   ...
   # backdrop_coordinator.gd exports: lateral_strength=28.0 use_dominant_grade=true
   # layer_streaks.gd: streak_alpha=0.35 ...
   ```
   Every emitted name must be an actual property that exists after WP1 — no orphan constants.

### The two presets

| Knob | CURRENT | PROPOSED (review starting values) |
|---|---|---|
| stars far / near rate | 0.005 / 0.02 | 0.01 / 0.03 |
| planet rate | 0.03 | 0.07 |
| far / mid / near rate | 0.2 / 0.5 / 1.2 | 0.18 / 0.45 / 1.8 |
| brightness far / mid / near | 0.2 / 0.4 / 0.6 | 0.2 / 0.5 / 0.95 |
| contrast far / mid | 0.0 / 0.7 | 0.5 / 0.7 |
| near rock min–max / pow | 72–308 / 3.0 | 110–308 / 1.6 |
| nebula alpha far / mid / near | 0.1 / 0.2 / 0.15 | 0.08 / 0.14 / 0.2 |
| streak speed / alpha / var-min | 750 / 0.6 / 0.8 | 480 / 0.35 / 0.5 |
| use_dominant_grade | off | on |
| lateral_strength | 0 | ~28 px (tune!) |
| drift_variance | 0 | 2.0 px/s |
| planet lateral_wander | 0 | 0.3 px/s ampl. |

PROPOSED values are **starting points for Roman to tune in this very lab** — the review's
numbers, not gospel.

### Verification for WP2
- `tools/parse_check.ps1` passes; lab launches from dev_menu headless-boot without errors.
- Manual: Roman drives it. Copy GDScript block inspected for real-destination names.

---

## WP3 — Phase 2 engine: composer fallback + palette authority (added 2026-07-08)

Roman's direction after driving the showcase: hold Phase 1 shipping; build Phase 2 into the
showcase, AND fix the dev/random generation sparseness — the empty-dict fallback gives 1–2
centered planets; he wants the full variety (nebulas, asteroid fields, systems) that
sector-map-driven combat gets.

Key fact: `scripts/parallax/stellar_composer.gd` ALREADY implements full-variety composition
(weighted system/planet/asteroid/nebula kinds, hero bodies, moons, nebula+asteroid overlays)
— written 2026-06-17 for precisely this regression, never wired in. WP3 wires it in and
extends it with the palette struct. Same inert-defaults philosophy as WP1.

### 3a. Composer fallback (inert flag)
- `backdrop_coordinator.gd`: new `@export var use_composer_fallback: bool = false`. When ON
  and `current_stellar` is empty, `_populate` builds the stellar dict via
  `StellarComposer.compose(rng, opts)` (preload-const, NOT class_name) instead of the bare
  inline fallback. The existing `rng` (already seeded from run/seed-override) drives it —
  `regenerate(seed)` determinism must keep working through the composer path.
- New coordinator field `forced_kind: String = ""` passed as `opts.kind` (showcase picker:
  Auto/system/planet/asteroid/nebula).
- `forced_planet_idx` must still win over the composer's pick when set.
- Production ships with the flag false → menus unchanged until a later one-line flip in
  `menu_backdrop.make()`.
- Fix the composer's false header comment (review P2) to describe the REAL wiring.

### 3b. Palette struct — derived FROM the composition, not imposed on it
`compose()` (and a new static `author_palette(stellar: Dictionary) -> Dictionary` usable on
sector-map dicts too) adds `stellar["palette"] = {key, dust, deep}`:
- `key` = star_color.
- `dust` = nebula band tint when a band is present, else a desaturated warm/cool bias
  derived from key (agent judgement; document the derivation).
- `deep` = a dark background bias (key darkened + desaturated, ~0.1 luma).
- `accent` is filled POST-SPAWN by the coordinator from
  `layer_planet.get_dominant_color()` (SDR-normalized, WP1) — the palette dict is stored on
  the coordinator (`var palette: Dictionary`) and completed in `_populate` after planet
  spawn, before `_apply_tints`/`_setup_composite`.
- Sector-map path: `_populate` calls `author_palette` when the incoming dict has no
  `palette` key, so combat gets a palette too without touching sector_map_v3 (dedup of its
  nebula table stays deferred to Phase 4 cleanup).

### 3c. Palette consumers (all behind `@export var use_palette: bool = false`)
When ON:
- `_apply_tints` + `_setup_composite` grade from `accent` (subsumes `use_dominant_grade`;
  keep that flag working independently — `use_palette` implies it).
- Nebula tint stays the band tint (it already IS `dust` by derivation — no change needed;
  assert this in code comment).
- Starfield: new `layer_stars.gd` export `key_tint: Color = Color.WHITE` + const
  `KEY_TINT_AMOUNT := 0.15` — star colors lerp toward key_tint at spawn (reseed respawns,
  so regenerate applies it). Coordinator sets it from `palette.key` when use_palette.
- Asteroid ramp: when use_palette and NO sector-map `asteroid_base_color` meta, ramp from
  `dust` instead of the neutral (0.9, 0.88, 0.85).
- Streaks: coordinator sets `streak_tint` from `accent` when use_palette (the showcase's
  per-section toggle keeps working — lab overrides after coordinator).
- OUT (deferred to combat integration): recycle-ghost retint — code hook noted in review §7,
  not exercisable in the showcase.

### 3d. WP3 verification
- parse_check; main boot clean; existing tools/test_parallax_showcase_api.gd still PASS.
- Extend that test: with `use_composer_fallback = true` + fixed seed, compose twice =
  identical dicts; across 40 seeds assert ≥3 distinct kinds appear, ≥1 has_asteroids,
  ≥1 nebula_band != ""; palette dict present with all 4 keys post-populate; with
  `use_palette` off assert layer modulates byte-identical to flag-on-but-default behavior…
  (i.e., flags-off run matches pre-WP3 snapshot values).

## WP4 — Phase 2 showcase UI (added 2026-07-08)

- New COMPOSITION section (top, above presets): `use_composer_fallback` is always ON in the
  lab; kind OptionButton (Auto/System/Planet/Asteroid/Nebula) → `forced_kind` +
  regenerate; Generate New now yields full-variety scenes. Show the rolled kind +
  nebula band + has_asteroids as a status line.
- New PALETTE section: master `use_palette` CheckButton + 4 color swatches (key/accent/
  dust/deep, live-updated each regen) + per-consumer CheckButtons (grade, stars,
  asteroids, streaks) — per-consumer OFF forces that consumer to legacy behavior (lab-side:
  temporarily unset the coordinator knob for that consumer; simplest is lab writes the
  legacy value after _apply_tints — agent judgement, document approach).
- PROPOSED preset turns use_palette ON; CURRENT turns it OFF. Persist all new keys in the
  JSON; Copy GDScript gains the new coordinator/layer_stars destinations.
- Verification: parse_check, lab headless boot, extend tools/test_parallax_showcase_lab.gd
  (kind force round-trip, palette swatch non-white after regen, Copy block names exist).

## WP5–7 — Roman's showcase-drive feedback round (added 2026-07-08)

Seven items from Roman's Phase-2 drive. WP5 (engine, scripts/parallax/* + composer) and WP6
(lab environment, scripts/dev/parallax_showcase.gd) run in parallel — disjoint files; WP7
wires WP5's knobs into the lab afterward. API names below are FIXED — deviations need
orchestrator sign-off.

### WP5 — engine (items 2, 4, 5, 6)

**Item 2 — planet jitter / pixel-snap toggle.** Planets at ~1.5 px/s step visibly.
INVESTIGATE FIRST: what res does the lab's backdrop SubViewport actually render at
(`HdScreen.add_upscaled_backdrop`) and where does snapping/rounding happen (project.godot
snap settings, layer code, pixel-parity)? Then: `layer_base.gd` gains
`@export var pixel_snap: bool = true` — true = today's behavior exactly; false = offsets
applied as raw floats (remove any explicit round/floor in the layer's scroll path, and if
viewport-level snapping is what quantizes, document that the toggle only helps at HD render
res). Roman explicitly accepts losing pixel-snap for background planets.

**Item 4 — asteroid count gradient (far > mid > near).** Mid is right. New coordinator
export `@export var asteroid_layer_mult: Vector3 = Vector3.ONE` (x=far, y=mid, z=near)
applied on top of density_mult in `_populate`'s count scaling (through the `_base_counts`
cache path). Default ONE = today. PROPOSED values: `(2.0, 1.0, 0.7)` (bases 4/5/3 →
8/5/2). Far minis should scale too.

**Item 5 — astral size variation.** Composer `_build_system` gets a star-mode roll:
- `distant_star` (~60%): star scale 0.06–0.14 (small, brilliant point — pair with a
  brightness/halo boost so it reads as "very bright but very small"), planets 0.15–0.95
  with the hero large.
- `near_star` (~40%): star scale 0.75–1.2 (dominant, outshines), planets 0.05–0.30.
Widen the single-planet path variance too (bigger spread than today's planet_size_variance
0.35 default — via the composer, not the export default). Star brightness boost: reuse the
HDR glow path (`PlanetGlowConfig` / halo) — small stars must still bloom. Stamp
`st["star_mode"]` for the lab status line.

**Item 6 — per-body parallax inside LayerPlanet.** New `layer_planet.gd` export
`@export var body_parallax: float = 0.0` (0 = today: whole layer scrolls as one).
When > 0: each spawned body gets `depth_mult` derived from its scale (bigger = nearer =
faster; star_mode-aware — a near_star is CLOSE so it moves fast, a distant_star barely),
applied as per-body `position.y` drift on top of the layer scroll (hook `_on_scrolled` or
`_process` with the scroll delta; lateral `apply_lateral` gets the same per-body scaling).
Wrap/cleanup must keep working. `body_parallax = 1.0` = full depth spread; PROPOSED = 1.0.

**Verification:** parse_check; both existing test suites still PASS (extend api test:
asteroid_layer_mult changes counts far>mid>near under forced asteroid kind; body_parallax=0
→ bodies byte-static relative to layer; star_mode appears in composed dicts across seeds).

### WP6 — lab environment (items 1, 3, 7)

**Item 1 — WorldEnvironment/bloom.** The lab's backdrop SubViewport has no WorldEnvironment,
so HDR glow (planet palettes, star halos) never blooms. Add combat's environment to the
lab's backdrop viewport: match `main.tscn`'s WorldEnvironment (glow enabled, intensity 0.8,
strength 0.75, blend 1, hdr_threshold 1.5) + whatever viewport HDR flag combat relies on
(`use_hdr_2d` — check how main renders vs the lab SubViewport; parallax_tuner.gd's
`_worldenv_on` toggle is prior art). Free it properly on exit (the old tuner leaked its
node — don't repeat).

**Item 3 — stretched panel.** WP4's additions stretched the control panel; rightmost
controls unreadable/clipped. Fix the layout: the panel must fit its column (proper
anchors/size flags/ScrollContainer, min widths on sliders instead of expand-greed).
Verify at the lab's actual window size.

**Item 7 — ship sprite.** `player_ship_a_body.png` is a 3-frame horizontal strip rendered
whole. Per project convention, menu-context ship visuals route through
`scripts/ui/ship_visual.gd` (player.tscn is the reference, never edit for a menu) — use it
if it drops in cleanly; else `hframes = 3, frame = 1`. Same playfield-band clamp.

### WP7 — lab wiring for WP5 knobs (after WP5+WP6 land)

- SCROLL section: planet `pixel_snap` CheckButton (CURRENT on, PROPOSED off — Roman's call).
- New DENSITY sliders: far/mid/near asteroid mult (0–3, live via regenerate-same-seed),
  CURRENT (1,1,1), PROPOSED (2.0,1.0,0.7).
- COMPOSITION status line gains `star_mode`; PALETTE/GRADE untouched.
- Planet section: `body_parallax` slider 0–1.5 (CURRENT 0, PROPOSED 1.0).
- Presets/JSON/Copy block updated (real names only); lab test extended for the new keys.

## Explicitly OUT of scope (this build)

- Changing any production default (the presets live in the lab; shipping PROPOSED = a later
  constant-paste commit via Copy GDScript).
- The full `current_stellar.palette` struct / StellarComposer re-wire (review Phase 2) —
  `use_dominant_grade` is the demonstrable slice of it.
- Bayer-dither nebula shader work, saturation term in `_recompute_modulate`, deleting
  V1/V2/V3 dead code, Nebula-Lab-knob landing sites (separate cleanup package).
- Recycle-ghost retint (depends on the palette struct).

## Sequencing / handoff state

1. **WP1** — engine knobs + fixes (agent build → advisor review → parse_check + API test).
2. **WP2** — showcase lab (agent build → advisor review → parse_check + boot test).
3. Roman drives the lab, tunes PROPOSED, exports via Copy GDScript.
4. Follow-on (separate): paste winners into `backdrop_coordinator.tscn` + exports = the
   review's Phase 1 ships.

If picking this up cold: WP1's knob table above is the API contract; WP2 §Controls is the UI
spec; the review doc holds the *why* for every value.
