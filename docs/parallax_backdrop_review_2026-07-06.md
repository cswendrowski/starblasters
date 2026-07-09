# Backdrop / Parallax System Review — 2026-07-06

Full-system review of the parallax layer stack, the Nebula Lab + Parallax Tuner dev tools,
the sector-map → backdrop data flow, and the visual composition (planetkit, asteroids,
nebula, recycler ghosts, grading). Three passes: architecture map, code review, visual
analysis. All claims verified against code; key ones spot-checked twice.

**Each numbered section is written to be extractable on its own for a targeted work handoff.**

---

## 1. System map (as-is)

**Live implementation = V4:** `scenes/parallax/backdrop_coordinator.tscn` →
`scripts/parallax/backdrop_coordinator.gd`. Instanced by production combat
(`scenes/main.tscn:16,96` — `drift_speed = 50`, `enable_hazard_decor = true`),
`signal_event.gd:44`, and menus via `menu_backdrop.gd` (`drift_speed = 14`).
`galaxy_backdrop.gd` (V1), `_v2.gd`, `_v3.gd` are **production-dead** (see §5).

The stack is **manual-scroll CanvasLayers** (not `ParallaxBackground`), all extending
`ParallaxLayerBase` (`layer_base.gd`). Coordinator `_process`
(`backdrop_coordinator.gd:350-356`) advances `drift_speed × delta`, each layer scrolls at
`scroll_rate ×` that. Back → front:

| Layer | CanvasLayer | rate | px/s @ combat 50 | Content |
|---|---|---|---|---|
| LayerStars | −10 | far 0.005 / near 0.02 (`layer_stars.gd:23-24`) | 0.25 / 1.0 | Two Parallax2D children (the one engine-parallax use); twinkling pinpricks |
| LayerPlanet | −8 | 0.03 (`layer_planet.tscn:8`) | 1.5 | PixelPlanets bodies, system dots, moons, black-hole halo |
| LayerStellarFar | −6 | 0.2, brightness 0.2, **contrast 0.0** | 10 | Shader asteroids 36–72px, minis, optional nebula |
| LayerStellarMid | −5 | 0.5, brightness 0.4, contrast 0.7 | 25 | Asteroids 75–150px, nebula |
| LayerStellarNear | −4 | 1.2, brightness 0.6 | 60 | Asteroids 72–308px (`size_pow 3.0`), nebula |
| LayerStreaks | −2 | self-driven particles, 600–900 px/s | — | Additive warp streaks |
| LayerComposite | −1 | — | — | Grade CanvasModulate + MUL GradeRect + vignette (`backdrop_coordinator.gd:316-347`) |
| Bg mines | world z −2/−1 | absolute 14/24/34 px/s | — | Minefield decor, self-drifting (`bg_mine.gd:11-15`) |

Nebula lives *inside* each stellar layer (`layer_stellar.gd:221-260`), screen-fixed by
countering `offset.y` while feeding `scroll_offset` to `nebula2.gdshader`.

**Sector map → backdrop:** on node click, `sector_map_v3.gd:2022/2082` writes
`Run.current_stellar` (`_compute_poi_stellar :665-755`) + `asteroid_base_color` meta.
Variation sources: node id ⊕ run_seed (deterministic, map/combat planets match), row →
star class/exotic/binary, hazard subtype → asteroids (belt-adjacency bonus) / minefield
decor, 40% nebula chance with band tints. **Faction is NOT an input anywhere.**
Coordinator `_populate` (`backdrop_coordinator.gd:92-198`) consumes the dict; empty dict
(menus, most dev tools) → bare inline fallback (random planet, no nebula/asteroids/system).

**Depth-matched foreground:** recycle ghosts (`recycle_controller.gd`), wrecks
(`wreck_layer.gd`), and mid-depth ships live in the world canvas as children of the
Backdrop node — **tree-order layering, no z_index** (`mid_depth_presentation.gd:46-53`).
`MidDepthPresentation` grade-matches by reading LayerStellarMid's live CanvasModulate.

**Tuner persistence contract:** `user://tuners/*.json` is session-only; production values
are baked constants Roman pastes from Copy GDScript. One exception: **production reads
`user://tuners/recycle.json` live** (`recycle_controller.gd:61-74`).

---

## 2. Why it feels "a little off" — four root causes

These four compound. Each alone is subtle; together they cap the depth illusion no matter
how much per-layer polish goes in.

### 2a. The scroll-ratio chain is bunched at the back and cliffed in the middle

Actual chain (at the default 22 px/s the tuner previews at):
stars-far **0.11** → stars-near **0.44** (4×) → planet **0.66** (1.5× ← bunched) →
far **4.4** (**6.7× ← cliff**) → mid **11** (2.5×) → near **26** (2.4×) →
gameplay 60–480 → streaks **600–900**.

- Stars-far, stars-near, and the planet all move ≤0.66 px/s — the planet takes ~1.5 s to
  move one pixel. The three deepest layers visually **fuse into one static plate**.
- The 6.7× planet→far cliff means the eye reads "frozen wallpaper, then moving rocks" —
  i.e. two-layer parallax, not seven.
- Streaks at 600–900 px/s exceed the game's own motion-clarity ceiling (480 px/s,
  `clarity.gd`) and render *behind* gameplay while *reading nearest* — a depth
  contradiction.

**Fix (S — 7 constants, tune via Parallax Tuner):** geometric ~2.2× spacing. Suggested
starting point: stars far 0.01, stars near 0.03, planet 0.07, far 0.18, mid 0.45,
near 1.8 (≈40 px/s — closes the gap to the slowest 60 px/s gameplay rung), streaks
clamped ≤480. Files: `layer_stars.gd:23-24`, `layer_planet.tscn:8`,
`layer_stellar_{far,mid,near}.tscn:8`, `backdrop_coordinator.gd:9`.

### 2b. Depth-brightness is inverted, and the far layer's tint is mathematically dead

- Nearest backdrop content is dimmed to 0.6 (`backdrop_coordinator.tscn:27-28`) — nothing
  in the backdrop ever reaches full value, compressing the whole range into murk.
  Atmospheric perspective wants **near ≈ 1.0, falling off with distance**.
- `LayerStellarFar` has `contrast = 0.0` (`backdrop_coordinator.tscn:21`).
  `_recompute_modulate` (`layer_base.gd:67-69`) computes `(base − 0.5) × contrast + 0.5`,
  so every channel collapses to 0.5 × brightness 0.2 = flat `(0.1, 0.1, 0.1)` **regardless
  of `modulate_color`**. The per-planet far tint written by `_apply_tints`
  (`backdrop_coordinator.gd:300`) is a no-op — dead work.

**Fix (S):** near 0.6 → ~0.95, mid 0.4 → ~0.5, far contrast 0.0 → ~0.5. Restores the
perspective ramp *and* un-kills the far tint. Pair with the §4 clarity cap so bright near
rocks don't fight bullets.

### 2c. Six independent color authorities — no shared palette

Confirmed root of "incohesive composition." Colors are picked independently by:

1. **Planet body** — `randomize_colors()`, fully random per seed (`layer_planet.gd:101,107`)
2. **Scene grade + layer tints** — `PLANET_TINT` keyed by planet *type*
   (`backdrop_coordinator.gd:29-39`); since the actual planet's palette is random, the
   grade regularly disagrees with the planet on screen (blue-rolled GasPlanet under a
   green type-tint). The V1 table even disagrees with V4 (GasPlanet purple in
   `galaxy_backdrop.gd:65`, green in V4) — two canons.
3. **Starfield** — fixed 7-color `STAR_COLORS` (`layer_stars.gd:3-11`), never level-tinted
4. **Nebula** — 5 fixed band tints, duplicated in `sector_map_v3.gd:656-662` and
   `stellar_composer.gd:23-29`
5. **Asteroids** — `asteroid_base_color` Run meta (row-picked, independent of the rest)
6. **Recycle ghosts** — fixed cool blue `(0.75, 0.85, 1.0)` (`recycle_controller.gd:50`)

**Fix (M — the highest-leverage structural change):** one **per-node palette struct**
authored once and carried in `current_stellar.palette`:
`{ key: star_color, accent: dominant planet color, dust: nebula/asteroid hue, deep: background bias }`.
`accent` should be sampled from the *actual* post-randomize planet — V1 already has
exactly this sampler (`galaxy_backdrop.gd:270-289`, brightest-color pick); port it into
`layer_planet` as `get_dominant_color()`. Then: `_apply_tints` uses `accent` instead of
`PLANET_TINT`; nebula tint = `dust`; starfield lerps 15% toward `key`; composite grade =
`accent` @ 0.09; ghosts multiply by `accent` (§2d). Delete the duplicate `PLANET_TINT`
table and the duplicated nebula-band palette. This is plumbing, not new visuals — every
consumer already takes a Color. Natural home: `StellarComposer` (see §6).

### 2d. Motion is a pure conveyor — nothing ever moves *against* anything

All layers scroll straight down at constant speed forever; the only non-vertical motion is
rock spin, twinkle, and `nebula_swirl 0.25`. **There is no horizontal parallax response to
player X** — the coordinator never reads the player. Rocks within a band move in perfect
lockstep (one shared `offset.y`); V1 had per-object drift variance
(`galaxy_backdrop.gd:955-963`) that V4 lost.

**Fixes, in payoff order:**
- **Horizontal parallax on strafe (M — biggest moment-to-moment depth payoff in the
  game):** feed `(player.x − Playfield.CENTER)` into the coordinator, offset each layer by
  `−dx × scroll_rate × k` (k ≈ 0.5, smoothed `lerp(…, 0.1)`). `offset.x` is unused;
  stellar wrap logic only checks Y (`layer_stellar.gd:293`) so X offsets are safe. Every
  strafe then *proves* the depth stack, 60×/s.
- **Per-rock lateral drift (S):** give each `_objects` entry a `vx` of ±1–3 px/s × band
  rate in `layer_stellar`.
- **Planet counter-drift (S):** ±0.3 px/s lateral wander — "massive body we're passing,"
  not "sticker."
- **Streak speed variance (S):** widen 0.8–1.2× → 0.5–1.2× (`layer_streaks.gd:34-35`).

---

## 3. Bugs (correctness)

### P0 — `seed(planet_seed)` reseeds the GLOBAL RNG at combat load
`layer_planet.gd:100` (and again per body in system mode, `:159`) calls global
`seed(planet_seed)` so PixelPlanets' `randomize_colors()` is deterministic. Side effect:
**all subsequent global-RNG gameplay rolls** (`asteroid.gd:89`, `bg_mine.gd:15`, every bare
`randf()` effect) start from a node-determined state on every entry/retry of the same node
— silently correlated "randomness" project-wide. Same pattern at `sector_map_v3.gd:987`
(menu-screen, lower stakes). **Fix (S):** capture/restore RNG state or `seed(randi())`
afterwards — one line per site.

### P1 — Nebula Lab mutates the live run seed
`nebula_lab.gd:189-191` does `run.set("run_seed", randi())` on every "New Backdrop" press,
purely to defeat the constant-seed problem below. `wave_generator._run_seed()` reads
`Run.run_seed` — visiting the lab mid-session changes an in-flight run's level generation.
**Fix (S/M):** give the coordinator a seed-override input (`regenerate(seed)` or export);
dev labs must never write into `Run`.

### P1 — "fresh seed" fallback is dead; Generate New regenerates the same thing
`backdrop_coordinator.gd:98-109`: the time-based-seed branch requires `run_node == null`,
but `Run` is an autoload — never null. Seed is constant within a session, so the Parallax
Tuner's "Generate New" (`parallax_tuner.gd:933`) produces the identical composition every
press, and the main-menu backdrop is identical every boot. The Nebula Lab hack above is
the symptom. Fixed by the same seed-override input.

### P1 — moons share one ShaderMaterial (last-write-wins)
`attach_moons` (`layer_planet.gd:427-497`) never calls `_duplicate_materials` before
`set_seed` (`:478`) — the exact shared-inline-material bug already documented and fixed
for asteroids (`layer_stellar.gd:113-118`). With 2+ moons, every moon renders the last
moon's surface, and the shared base material is left dirty. `spawn_planet`,
`spawn_system_body`, `_spawn_companion_body` all duplicate; moons are the one missed path.
**Fix (S):** one line.

### P2 — starfield is byte-identical every level of every run
`layer_stars.gd:27` constant seed `12345`; `reseed()` exists but only
outpost_arrival/loading_screen call it. `_populate` never reseeds LayerStars.
**Fix (S):** `star_layer.reseed(rng.randi())` in `_populate`.

### P2 — pixel-parity contract violation in the sector map
`sector_map_v3.gd:980,990` calls `set_pixels(display_px)` **before** `add_child(p)` — the
order CLAUDE.md forbids. `_reset_planet_colorrects` partially compensates but the site is
out of contract. Every layer_planet site follows it correctly.

### P2 — Parallax Tuner leaks a WorldEnvironment node
`parallax_tuner.gd:117-127,220-229`: `_we_node` created unconditionally, only added to the
tree when the toggle is on (off by default) → orphan on exit. Free in `_exit_tree()`.

### P3 — misc
- `backdrop_coordinator.gd:354` string-probes `"scroll_rate" in layer` every frame per
  layer; layers are all `ParallaxLayerBase` — type the array.
- `layer_planet.gd:76,138` silent DryTerran fallback on bad index — `push_warning` it.
- `nebula_lab.gd:462` local `var str` shadows the built-in.
- `parallax_tuner.gd:730` stale comment (planet types now go through Rivers, 11 types).
- `layer_stellar.gd:309-324` baked-rock tick allocates a `Rect2` per rock per frame —
  only matters if backdrops go dense; perf-runner territory.
- V1's `_apply_pixel_parity` (`galaxy_backdrop.gd:1099`) lacks the anchor-normalize
  SIGSEGV fix — the three capture tools still on V1 can hit the known PixelPlanets crash.

---

## 4. Playfield clarity

Mostly disciplined: conservative nebula alphas (0.1/0.2/0.15), MUL vignette darkens
corners to 0.74, bloom gated at `glow_hdr_threshold 1.5`. Two offenders + one inversion:

- **Warp streaks are the one backdrop element mistakable for a projectile** — additive
  white @ alpha 0.6, 2×28px vertical lines at 600–900 px/s: same shape grammar, same axis,
  *faster* than player lasers. **Fix (S):** clamp ≤480 px/s, alpha → ~0.35, tint from the
  level palette (`layer_streaks.gd:34-44`, `backdrop_coordinator.gd:9`).
- **Near rocks up to 308px** cross behind the 216px play band. Once §2b brightens the near
  band, add a compensating rule: rocks over ~140px keep the dim (or alpha 0.85). Better:
  adopt an explicit **max-luminance budget** — nothing in the backdrop inside X 132–348
  exceeds ~0.65 luma except the planet body. Currently implicit; make it a stated rule in
  the coordinator + a tuner readout.
- **Nebula alpha ordering is non-monotonic** (far 0.1 / mid 0.2 / near 0.15) — a mild
  depth inversion; make it 0.08/0.14/0.2.
- **Mid/near size overlap:** median near rock ≈ 101px (`size_pow 3.0` over 72–308) vs
  median mid ≈ 106px — the typical near rock is the *same size* as the typical mid rock
  while moving 2.4× faster. The two strongest depth cues disagree. **Fix (S):** near min
  72 → ~110, or `size_pow` 3.0 → 1.6 (`layer_stellar_near.tscn:12-14`).

---

## 5. Dead code & streamlining

~2,200 lines of dead backdrop steering readers (and agent briefs) wrong:

| Item | Status | Action |
|---|---|---|
| `galaxy_backdrop_v2.gd` (300 ln) | zero references | delete |
| `galaxy_backdrop.gd` V1 (1,263 ln) | 3 capture tools only (`capture_engine_torch/horizontal_proof/poi_moons`) | port tools to `backdrop_coordinator.tscn`, delete |
| `galaxy_backdrop_v3.gd` (614 ln) | `capture_v3_standalone.gd` only | delete both |
| `layer_stellar` mine path (`mine_count`, `_spawn_bg_mines`, `:26,263-282`) | never driven; duplicate of coordinator's live spawner | delete (or route coordinator through it — pick one) |
| `stellar_composer.gd` header (`:10-12`) | claims call paths that don't exist; sole caller is combat_vfx_lab | **keep the file** (planned re-introduction per `docs/parallax_rework_safe_rebuild_2026-06-18.md:248`) but fix the header |
| Duplicated nebula-band palette | `sector_map_v3.gd:656-662` ≡ `stellar_composer.gd:23-29` | single-source (falls out of §2c) |
| Duplicated PixelPlanets control-anchor setup | `layer_planet.gd:82-88,143-150,390-401,455-466`, `layer_stellar.gd:95-101` | extract one helper (sector_map already did: `_setup_celestial_control`) |
| Stale docs | `CLAUDE.md:82` + `.claude/agents/vfx-author.md:14` point at V1 (godot-explorer.md correctly says dead — briefs contradict); `ui_designer.gd:15` comment; `run_state.gd:87` lists a `star_distance_ratio` key nothing emits; `outpost.gd:169` | update alongside the deletion |

Config triplication: `drift_speed` = 22 (script default) / 50 (main.tscn) / 14 (menu) —
**the tuner previews at 22; nobody ever tunes at the combat-live 50.** At minimum the
tuner should boot with combat's values.

---

## 6. Tuner pipeline gaps

The Copy-GDScript contract is satisfied in letter, broken in spirit for the nebula:

- **Nebula Lab exports have no landing site.** `nebula_lab.gd:611-622` emits
  `NEB2_FAR/...` constants **no production code consumes**. The production nebula
  hardcodes `warp_strength 0.8 / wisp_strength 0.2 / opacity 1.0`
  (`layer_stellar.gd:251-258`) — the very knobs the lab tunes. Roman's tuned config
  physically cannot flow in. **Fix (M):** promote those to exports/consts on
  `layer_stellar` (or a small NebulaConfig) that the Copy block targets. Same for the
  lab's per-layer Far/Mid/Near placement + AltB shader — currently lab-only.
- **Parallax Tuner exports** (`LAYER_COLORS/…`, `parallax_tuner.gd:1044-1081`) also match
  no production names — real values land as hand-edited `.tscn` overrides
  (`backdrop_coordinator.tscn:20-28`). Workable but drift-prone; at minimum name the
  emitted block after the actual destination.
- **Production knobs with no tuner:** coordinator system-staging KNOBs (`SYS_X_MIN…`,
  `backdrop_coordinator.gd:47-62`, literally commented "Roman to tune"),
  `BELT_DENSITY_SELF/ADJACENT` + `NEBULA_NODE_CHANCE` (`sector_map_v3.gd:589-590,655`),
  bg-mine depth-band table, `nebula_swirl`, per-layer `asteroid_size_pow`.
- **What works:** `AUTO_TINTED_LAYERS` correctly refuses to bake runtime per-planet tints;
  PlanetGlowConfig's baked-DEFAULTS-with-tuner-JSON split; recycle tuner's live JSON read.

**Structural recommendation:** re-wire `StellarComposer` as the single authority it was
designed to be — coordinator calls it when `current_stellar` is empty (menus/dev get the
full composed look instead of the bare fallback), it owns the §2c palette struct, and it
takes an explicit seed (fixing both P1 seed findings). This was already the plan in the
2026-06-18 safe-rebuild doc; it's the one refactor that fixes seeding, menu quality,
palette cohesion, and the dead fallback branch simultaneously.

---

## 7. Recycle ghosts vs. depth grammar

The ghost pass impersonates the mid band but breaks its rules
(`recycle_controller.gd:40,50,292-311`):

- **Hue:** fixed cool blue regardless of level grade — on a lava/amber node it's the only
  cold object on screen. Once §2c's palette exists, multiply the stored tint by
  `palette.accent` (or read the mid layer's `modulate_color`, which
  `MidDepthPresentation.read_mid_layer_grade` already knows how to do) in
  `_apply_ghost_look`. One line.
- **Brightness:** mid band renders under a 0.4-brightness CanvasModulate; the ghost's
  0.75–1.0 tint is ~2× brighter than genuine mid-depth content → reads holographic, not
  distant. Scale RGB by ~0.55 to sit on the darkening curve.
- Scale 0.45 is fine — consistent with mid/far once the tint is corrected.

Also note `WreckLayer` self-grades to the NEAR layer's **baked** CanvasModulate
(`wreck_layer.gd:47-54`) — if §2b changes the near brightness, wrecks follow automatically
(good), but re-check after tuning.

---

## 8. Prioritized roadmap

**Phase 0 — bug fixes (S, no visual-design decisions needed):**
1. Global-RNG reseed fix at `layer_planet.gd:100,159` (+ sector_map copy)
2. `_duplicate_materials` in `attach_moons`
3. Reseed LayerStars from `_populate`
4. Coordinator seed-override input; Nebula Lab stops writing `Run.run_seed`; tuner
   "Generate New" actually generates new
5. Tuner WorldEnvironment orphan; tuner boots at combat `drift_speed 50`

**Phase 1 — constant retune (S, all through the Parallax Tuner, Roman-driven):**
6. Re-space scroll ratios to ~2.2× geometric steps (§2a)
7. Brightness ramp near→0.95 / mid→0.5 / far contrast→0.5 (§2b)
8. Near-rock size floor (§4) + monotonic nebula alphas
9. Streaks: ≤480 px/s, alpha 0.35, wider variance

**Phase 2 — palette unification (M, the structural fix):**
10. `current_stellar.palette` struct owned by StellarComposer; port V1's dominant-color
    sampler; all six color authorities sample it; delete duplicate tables (§2c)
11. Recycle ghost tint × accent, ×0.55 brightness (§7)
12. Re-wire StellarComposer as the empty-dict fallback (menus get composed backdrops)

**Phase 3 — motion depth (M):**
13. Horizontal parallax on player X — the single biggest depth payoff (§2d)
14. Per-rock lateral drift + planet counter-drift

**Phase 4 — cleanup (M, any time):**
15. Delete V1/V2/V3 + port 4 capture tools; fix CLAUDE.md/agent briefs/stale comments
16. Nebula Lab knobs → real production exports on `layer_stellar` (§6)
17. Optional polish: Bayer dither on far nebula alpha (quantized to existing `pixels`
    cells), saturation term in `layer_base._recompute_modulate` (true
    desaturation-with-distance), starfield 15% key-color lerp

Phases 1–3 are independent of each other; Phase 2 unblocks the ghost/streak tinting in
1 and 3 but partial versions ship standalone (item 6 of the visual top-10: dominant-color
grade without the full palette struct).

---

## Appendix — what's already good (don't churn)

- The live pixel-parity implementation (`layer_planet.gd:239-273`) is the best it's been:
  anchor normalization (the SIGSEGV fix), canonical ColorRect table, contract honored at
  all four spawn sites with *why* comments.
- The coordinator is genuinely data-in: reads `current_stellar` + one meta key, pushes
  plain properties; layers never reach back into Run. `enable_hazard_decor` default-off
  correctly keeps stale hazard decor out of menus.
- `_halo_tex_cache` pow2 bucketing and per-instance material duplication in
  `_spawn_asteroid` show the shared-resource gotchas are known — the moons miss (§3) is a
  targeted fix, not a rewrite signal.
- Determinism discipline: node-id ⊕ run_seed with map/combat consumption-order matching
  (`sector_map_v3.gd:764-769`) so the map's planet *is* the combat planet.
- Twinkle phase/hz variance, two-size star split, occlusion ordering, 35% rock spin — the
  right cues exist; they're undermined by the ratio/brightness constants, not missing.
