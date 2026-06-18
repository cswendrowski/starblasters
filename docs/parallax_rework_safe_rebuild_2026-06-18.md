# Parallax Rework — Safe Rebuild Plan (2026-06-18)

> **Status: PROPOSAL.** Drafted for Roman to review. The numbers/caps and the
> increment order are starting points to nail down together, not final.

## 0. TL;DR

The 2026-06-17 parallax rework crashed the game (SIGSEGV) intermittently at **scene
transitions**. We reverted it to the baseline backdrop to restore stability. This doc
plans how to re-land its visual gains (colored star glows, varied starfields, random-gen
fallback, asteroid fields) **without** the crash. The core fix (§4a) is to **isolate the
combat backdrop in a `SubViewport`** — the pattern the parallax tuner and sector map already
use safely; combat is the only context rendering the backdrop directly, and that's exactly why
it crashes when `change_scene` frees it. With the backdrop isolated, the planet "cap" becomes a
**performance budget** rather than a crash limit, so we keep the dense multi-body arrays and use
LOD (full shader → baked sprite → glowing dot, by distance) + flat static asteroids to keep
render cost flat.

## 1. What happened

The rework (`61aaf6b1` "random-gen fallback + colored star glows + varied starfields;
asteroid + shader-lab fixes") added:

- **`StellarComposer`** — random-gen stellar fallback for contexts with no sector-map data
  (menus, dev tools, the parallax tuner).
- **Colored star glows** — the star body's bloom/halo takes the row's star colour.
- **Varied starfields / per-node varying seed** — the backdrop now varies per node / over
  time instead of being pinned to one constant seed every combat.
- **Restored asteroid fields** — a density fallback that fixed the prior bug where asteroid
  POIs silently spawned ~0 decorative asteroids.

After it landed, combat began crashing to desktop (signal 11) intermittently — **both** on
entering a combat level **and** on clearing one / returning to the sector map. Reverted the
four rework files (`backdrop_coordinator`, `layer_planet`, `layer_stellar`,
`parallax_tuner`) to baseline `1475c4e2`; `stellar_composer.gd` is now orphaned dead code
kept in-tree for the rebuild.

## 2. Root cause (established from the logs)

- **Symptom:** a flood of `ERROR: Parameter "canvas_item" is null` at
  `canvas_item_set_draw_index (renderer_canvas_cull.cpp:1917)` → SIGSEGV. **220** of them on
  Forward+ / Vulkan; **14** on the Mobile renderer. Same bug, both renderers — not a
  mobile-only or pipeline-compile artefact.
- **When:** during `change_scene_to_file` — the `change_scene (scene_transition.gd:46)`
  frame is the one constant across every crash backtrace (combat load *and* return-to-map).
  The engine reindexes CanvasItem draw order as the outgoing scene is freed; with enough
  freed shader CanvasItems in the batch it walks a null/freed RID and dies.
- **Why the backdrop:** the combat backdrop is `scenes/parallax/backdrop_coordinator.tscn`
  — a **`Node2D`** with `LayerStars / LayerPlanet / LayerStellarFar/Mid/Near / LayerStreaks
  / LayerComposite` as **direct children, all z=0, NO SubViewport isolation**. Its
  PixelPlanets are shader-driven Control/ColorRect trees; asteroids are per-instance
  shader-materialed scenes. So when `change_scene_to_file` frees the combat scene, the whole
  backdrop's shader CanvasItems free in one batch *alongside* enemies/bullets/FX, and the
  reindex over that batch is what faults.
- **Why it was load-dependent / intermittent:** the baseline backdrop used a **constant
  seed** → the same, lighter config every combat (and the density-0 bug meant asteroid POIs
  had ~0 rocks). That stayed under the engine's reindex threshold. The rework's **varying
  seed** rolled heavier/varied configs (more/heavier shader planets, real asteroid fields),
  which intermittently cross it. The last captured crash was a *planet* POI with **no
  asteroids** returning to the map — confirming it's the general backdrop teardown load, not
  asteroids specifically.
- This is the same PixelPlanet/SubViewport fragility tracked in the
  `planet-pixel-parity-sigsegv` memory, but the trigger here is **scene-swap teardown**, and
  the `_normalize_colorrect_anchors` "size overridden" fingerprint is **absent** — so it is
  *not* the anchor-override variant; it's raw freed-CanvasItem-during-reindex.

## 3. Goal

Re-land the rework's visual gains with **zero** transition crashes across a full multi-sector
run, on the real Forward+ renderer.

## 4. Approach — defense in depth

### 4a. PRIMARY: isolate the combat backdrop in a SubViewport (proven, in-codebase pattern)

**This is the structural fix** and it's already proven elsewhere in this project (Roman's
catch, 2026-06-18 — confirmed):

- **Parallax Tuner** (`parallax_tuner.gd:70-92`) creates a `SubViewport` + `SubViewportContainer`
  (480×270 @ 4×) and instantiates the **full `BackdropCoordinator` INTO the SubViewport**. Stable
  under constant rebuild.
- **Sector Map HD** (`sector_map_hd.gd:90-103`) embeds `sector_map_v3` in a `SubViewport`;
  `sector_map_v3` spawns real PixelPlanets + asteroids + stars inside it. Stable.
- **Combat (`main.tscn`) is the lone outlier** — the `Backdrop` (`BackdropCoordinator`) is a
  DIRECT `Node2D` child, **no SubViewport**.

A SubViewport owns its own canvas/World2D. Freeing a SubViewport-embedded backdrop tears that
canvas down **as a unit** — no per-item `canvas_item_set_draw_index` reindex against the main
scene's canvas. The direct combat backdrop is reindexed item-by-item as `change_scene` frees it
→ the 220-null flood. **Empirical proof from Roman's play-tests: `map→combat` (frees the
SubViewport-embedded map) has NEVER crashed; `combat→map` (the direct backdrop) is exactly where
it does.** The tuner also builds/rebuilds backdrops in its SubViewport without issue → this should
fix the **load** burst too, not just teardown.

**The fix:** wrap the combat backdrop in a `SubViewportContainer` + `SubViewport` exactly like the
tuner/map. The one real cost is a **layering refactor**: today the backdrop is z=0 in the world
with ships/bullets and the mid-depth seam (cruiser, wreck via `MidDepthPresentation.add_above_backdrop`)
and parallax shadows rendering above it. Moving the backdrop into a back-most `SubViewportContainer`
keeps everything else in the main world rendering over it — the "above backdrop / below ships"
ordering is preserved, but the mid-depth + parallax-shadow seams must be re-homed. Tractable; that's
the bulk of the work. **Validate with the §6 harness before committing.**

### 4a-bis. BACKSTOP: controlled teardown before the scene swap (`on_covered`)

`scene_transition.gd::change_scene` already accepts an `on_covered` callback that runs once the
screen is fully black, **before** `change_scene_to_file`. Add `BackdropCoordinator.teardown()`
(`remove_child` before `queue_free`) and call it from `on_covered` on exit transitions, plus from
`NOTIFICATION_EXIT_TREE` as a defensive backstop. With 4a in place this is belt-and-suspenders, not
the primary — but cheap, and it covers any path that bypasses the SubViewport (e.g. dev launches).

### 4b. PERFORMANCE: LOD-by-distance, so "cap" = a render budget, not a crash limit

Once 4a isolates the backdrop, the planet cap **stops being a crash-safety limit and becomes a
pure performance budget** — so we keep Roman's striking 5–6-body arrays. The system already
models *distance* (near = full body, far = dot), so LOD is the natural lever. Render each body at
the cheapest tier that holds its visual fidelity at its distance:

| Tier | Use for | Cost |
|---|---|---|
| **Full animated shader PixelPlanet** | nearest 1–2 hero bodies | per-frame shader (expensive) |
| **Static baked sprite** | mid-distance bodies | render the procedural planet to a texture ONCE, then a flat `Sprite2D` — no per-frame shader, ~free |
| **Glowing colored dot** | far bodies | trivial (already supported via `spawn_system_dot`) |

- **Generous "cap"** = how many *full animated* shader planets we afford per frame (the harness
  measures the perf sweet spot; likely 1–3). Everything beyond that distance-threshold becomes a
  baked sprite or dot — visually identical at distance, near-free to render.
- **Asteroids → flat static sprites** instead of per-instance shader `Asteroid.tscn`. Drops the
  `ShaderMaterial.duplicate()` per rock entirely; flat sprites are cheap and a distant tumbling
  rock reads fine without the procedural shader. (Bake a few rotation/shape variants to a small
  atlas, or pre-render per spawn.) This also shrinks the SubViewport's per-frame draw load.
- **Baking mechanics (open):** a one-time render-to-texture (a transient `SubViewport` snapshot of
  the PixelPlanet) gives an exact match; a curated set of pre-made planet/asteroid sprites is
  simpler but less varied. Decide per §5.
- Build-side still worth keeping even with 4a: **defer** `_populate` off the `change_scene`/`_ready`
  frame, and the asteroid **stagger** (a few per frame) — cheap insurance against any residual
  build burst.

### 4c. Re-introduce INCREMENTALLY (land + test each)

Re-land in small, individually-verified steps so we keep the safe parts and isolate any
remaining trigger. Suggested order, lowest-risk first:

1. **Colored star glows** — cosmetic, ~no canvas-count delta.
2. **`StellarComposer` random-gen fallback** (menus / dev tools) — test menu/dev transitions.
3. **Varied starfields / per-node varying seed** — the suspected primary trigger; test
   combat-in and clear-out hard.
4. **Asteroid fields** (heaviest) — last, with the 4b cap + stagger.

Each step: a couple of full sectors clean before moving on.

## 4d. Spawn model — keep the recycle pool; the bursts are the bug (Roman's Q, 2026-06-18)

**How asteroids spawn today:** `layer_stellar.populate()` creates the WHOLE field up front
(`asteroid_count` + `mini_asteroid_count` per layer × 3 stellar layers, one frame), spawned above the
screen. `_on_scrolled()` (layer_stellar.gd:237) **recycles** each one — repositions it back above the
top when it scrolls off the bottom; nodes are **never freed during gameplay**. Frees happen only in
`_clear_content()` on `populate()`/reset (i.e. level change). So it's a **fixed recycled pool**, not a
spawn-as-needed stream.

**Recycle is the right model — do NOT switch to spawn-as-needed (enemy style).** The crash is about
*freeing* CanvasItems during the draw-order reindex; the pool frees nothing during play, so its risk is
confined to two controllable moments (create-at-load, free-at-`change_scene`). A spawn-stream would push
freeing into live gameplay (crash mid-fight, not just at a transition — far harder to contain) AND
re-pay `Asteroid.tscn`'s per-instance `ShaderMaterial.duplicate()` on every spawn (continuous material-RID
churn = more crash surface + GC). Note: *main* asteroids are the shader-heavy ones (default
`asteroid_count = 4`/layer ≈ 12–18 total); *mini* asteroids are plain 1–2px `ColorRect`s (cheap).

**Three levers, cheapest → most robust** (decide which to take):
1. **Stagger creation + clean teardown** (§4a/§4b) — keeps the per-scene backdrop; fixes both bursts.
   Smallest change.
2. **Shrink the pool** — we keep every asteroid alive as the off-screen drift buffer; size it toward
   "visible + small buffer" to cut the shader-asteroid count directly. Pure tuning.
3. **Persistent backdrop** — the root is that the backdrop is part of each combat/map scene, so it's
   created+freed on EVERY transition. Move it to a persistent layer that survives scene changes and just
   re-tints/re-seeds per POI → its CanvasItems are NEVER in a `change_scene` free batch → eliminates the
   crash class outright (and removes the backdrop "pop" between scenes). Bigger refactor (relocate it out
   of the scenes, manage z-order centrally, re-target on context change), but the architecturally correct
   fix. Strongly consider this as the target end-state, with §4a/§4b as the interim.

## 5. Open questions (to settle together)

- **SubViewport audit — ANSWERED (2026-06-18).** Tuner + sector-map already run the PixelPlanet
  backdrop in a SubViewport and don't crash; combat is the only direct one. Remaining question is
  the *layering refactor* (§4a): re-home the mid-depth seam (cruiser/wreck) and parallax shadows
  now that the backdrop sits in a back-most `SubViewportContainer` rather than z=0 in the world.
  Audit `MidDepthPresentation.add_above_backdrop` + `ParallaxShadow` callers.
- **Full-shader budget (the "generous cap").** How many full *animated* shader planets per frame
  before frame-time suffers (harness-measured) — that's the LOD threshold; beyond it → baked sprite,
  then dot. Likely 1–3 full. Decoupled from crash-safety now.
- **Baking mechanics.** Static mid-distance planets + static asteroids: render-to-texture
  (transient SubViewport snapshot → exact match, more plumbing) vs a curated pre-made sprite set
  (simpler, less varied)? Affects how the composer chooses a body's tier.
- **Frame-deferred backdrop OK?** Deferring `_populate` a frame or two is covered by the fade-in —
  confirm it reads cleanly.
- **One SubViewport or per-layer?** Whole backdrop in one SubViewport (simplest) vs splitting the
  parallax depth layers — one SubViewport is almost certainly right; note here in case scrolling/
  parallax math wants otherwise.

## 6. Verification plan

- **Minimal repro harness** (build first): a scene that stages N backdrop planets/asteroids
  then forces a `change_scene`, run windowed on Forward+. Establishes the crash reproduces at
  some N, pins the threshold, and proves `teardown()` + caps eliminate it. The crash **never
  shows headless** (dummy renderer skips the GPU/canvas path) — must be the real renderer,
  windowed.
- **Per-increment:** `tools/parse_check.ps1` + a couple of full sectors (combat load +
  clear→map) on Forward+. Capture with `tools/run_vulkan.bat` if anything recurs.
- **Final:** a full multi-sector run clean, plus a transition sweep
  (menu ↔ combat ↔ map ↔ summary ↔ outpost).

## 7. Files in scope

SubViewport isolation (§4a, primary):
- `scenes/main.tscn` — wrap the `Backdrop` in a `SubViewportContainer` + `SubViewport` (mirror
  `parallax_tuner.gd:70-92` / `sector_map_hd.gd:90-103`); backdrop becomes back-most.
- `scripts/game/main.gd` — re-home the mid-depth seam now that the backdrop is in a SubViewport:
  `MidDepthPresentation.add_above_backdrop` (cruiser/wreck) + `ParallaxShadow` callers.
- `scripts/effects/parallax_shadow.gd` / `scripts/.../mid_depth_presentation` — shadow/mid-depth re-home.

LOD + spawn model (§4b/§4d, performance):
- `scripts/parallax/layer_planet.gd` — LOD tiers (full / baked-sprite / dot by distance);
  `remove_child`-before-free in `clear_planet` (backstop).
- `scripts/parallax/layer_stellar.gd` — flat static-sprite asteroids; cap + stagger spawn;
  `remove_child`-before-free in `_clear_content` (backstop).
- `scripts/parallax/backdrop_coordinator.gd` — `teardown()` (backstop), deferred `_populate`,
  full-shader budget.
- `scripts/parallax/stellar_composer.gd` — re-introduce (currently orphaned post-revert); have it
  assign each body a render tier.

Backstop + re-land:
- `scripts/systems/scene_transition.gd` — `on_covered` already supported; wire it for the teardown backstop.
- `scripts/screens/sector_map_v3.gd` / `sector_map_hd` — already SubViewport-isolated; reuse for LOD parity.
- `scripts/dev/parallax_tuner.gd` — re-introduce the rework's tuner support + LOD-tier preview.

## 8. What the revert traded away (to restore)

Colored star glows; varied starfields; the random-gen backdrop for menus/dev tools; restored
asteroid fields. The backdrop is currently back to the simpler, constant-seed baseline look.
