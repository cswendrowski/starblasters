# Scene light direction — one source of truth

**Status: L1 + L2 + L3 ALL BUILT — UNPLAYTESTED** (2026-07-28). **Canonical azimuth is 225°
(up-left) — Roman's call, 2026-07-28.** `scripts/systems/scene_light.gd` is the SSOT; every consumer
in §2 derives from it, so the scene has ONE sun, and that sun now swings 207°–243° with the level's
position in its star system (§4). Nobody has looked at any of it yet — it is correct by construction
and by test, not by eye. Regression guard: `tools/validate_scene_light.gd` (must print
`VERDICT: PASS`) — it pins the values that must never move, checks the re-lit consumers land on
canonical, fails if any converted file reintroduces a private sun literal, and covers the
star-reactive rule end to end. Cross-cutting design: unify where "the light comes
from" across PlanetKit planets, PlanetKit asteroids, building drop shadows, ship drop shadows, and
the incoming starbase decks — so the direction can be moved in one place, and so star-reactive
lighting can later drive all of them together. Raised during
[`starbase_assault_design_2026-07-28.md`](starbase_assault_design_2026-07-28.md) §5.2.

---

## 1. The problem: four different suns

Measured from live code, not from intent. Godot screen convention (+Y down), azimuth measured from
+X, and "light azimuth" normalized to *where the light sits relative to the object*:

| system | representation | live value | light azimuth |
|---|---|---|---|
| PlanetKit planets (combat backdrop) | `set_light(uv)` | `Vector2(0.0, 0.5)` — `layer_planet.gd:239,314,484` | **180° — due left** |
| PlanetKit asteroids (sector map) | `set_light(uv)` | `Vector2(0.0, 0.5)` — `sector_map_v3.gd:884,918` | **180° — due left** |
| Baked parallax asteroids | `light_origin` uniform | `ang = 225°` — `asteroid_bake_cache.gd:98` | **225° — up-left** |
| Stronghold rock, un-baked asteroids | shader default | `vec2(0.39, 0.39)` — never set | **225° — up-left** |
| Building drop shadows | `sun_dir` (**shadow** direction — see §1.1) | `(0.7071, 0.7071)` — `BuildingShadow.DEFAULTS` | **225° — up-left** |
| Ship/enemy drop shadows on rocks | `SHADOW_DIR` (shadow direction) | `(0.35, 0.9)` — `AsteroidShadowRig:25` | **≈249°** |
| Ship/enemy drop shadows on flyover | `SHADOW_DIR` (shadow direction) | `(0.35, 0.9)` — `flyover_backdrop.gd:34` | **≈249°** |
| Flyover planet surface (hillshade) | `sun_dir` (**light** direction — see §1.1) | `(0.40, 0.35)` — `flyover_backdrop.gd:342` | **≈41° — down-right** |

So: **180°, 225°, ~249° and ~41° are all live simultaneously.** The two most prominent objects on
screen are the two outliers — the backdrop planet at 180°, and (on flyover levels) the whole
scrolling ground surface at ~41°, which is *roughly opposite* the 225° majority. Flyover fires on a
large share of planet-POI combats, so that opposite-sun surface is not a corner case.

Provenance of the 249° outlier: `AsteroidShadowRig.SHADOW_DIR` was ported verbatim from the Planet
Flyover lab's *cloud* shadows, where a near-vertical offset represented cloud height over a
scrolling surface. Carried onto side-lit rocks, it reads as a different sun. Note the flyover
backdrop still holds its **own copy** of that constant — the two are identical today only by
duplication, so converting one without the other lets them drift.

Two more consumers are **dormant, not live**, both gated `SHADOWS_ENABLED = false` and both disabled
2026-05-30 "pending a dedicated shadow pass" — which is this document:

| system | representation | value | light azimuth |
|---|---|---|---|
| `ShadowFx.attach_shadow` (per-sprite oblique) | `DEFAULT_OFFSET_WORLD` | `(8, 8)` — `shadow_fx.gd:20` | 225° |
| `ParallaxShadow.attach` (ground ellipse) | `SHADOW_OFFSET` | `(10, 14)` — `parallax_shadow.gd:24` | ≈235° |

They don't contribute to the count today, but if either is re-enabled it must derive from
`SceneLight`, not re-hardcode a third and fourth offset.

### 1.1 `sun_dir` is not one convention

Two shaders take a uniform named `sun_dir` and mean **opposite things** by it:

- `graphics/building_shadow.gdshader` — `trace()` marches `uv -= step_uv` (`:75`), i.e. *against*
  `sun_dir`, looking for the occluder between the pixel and the light. So the light is at
  `-sun_dir`: **the uniform is the shadow direction.** Its own comments (`:14`, `:28`, `:66`) claim
  it is the light direction and are wrong — fix them as part of L1 before anything derives from
  them.
- `graphics/planet_ground.gdshader` — `hillshade()` returns `-(∇h · normalize(sun_dir))` (`:155`),
  the textbook lambert form, matching its "Positive = slope faces the sun" comment. There
  **`sun_dir` is the light direction.**

So `SceneLight.shadow_dir()` feeds `building_shadow`, and `SceneLight.light_dir()` feeds
`planet_ground`, through a uniform of the same name. Every conversion in §2 states which.

### Azimuth vs radius — keep them separate

`light_origin` is a UV-space *point*, encoding two things at once:

```
light_origin = vec2(0.5, 0.5) + radius * vec2(cos(azimuth), sin(azimuth))
```

- **azimuth** — where the light is. This is what needs unifying.
- **radius** — how far the terminator is pushed across the sprite (softness / how much of the body
  is lit). `0.1556` (kit default), `0.45` (baked rocks), `0.5` (planets — terminator right at the
  sprite edge, a flat half-lit read).

**Unify azimuth; preserve each consumer's existing radius.** Changing radius as a side effect would
re-light the planets well beyond their direction, which is not what's being asked for.

---

## 2. Proposed: `scripts/systems/scene_light.gd`

A tiny stateless module, same shape as `Playfield` — constants plus pure conversion helpers, no node,
no autoload.

```gdscript
class_name SceneLight
extends Object

# THE canonical direction. Everything that casts a shadow or lights a body derives from this.
const DEFAULT_AZIMUTH_DEG: float = 225.0     # up-left (see §3 for why)

# Per-consumer terminator radii, preserved from what each already used (see §1).
const RADIUS_PLANETKIT_DEFAULT: float = 0.1556
const RADIUS_BAKED_ROCK:        float = 0.45
const RADIUS_PLANET:            float = 0.5

static func azimuth_deg() -> float
    # DEFAULT_AZIMUTH_DEG, or the per-level override published at level start (§4).

static func light_dir() -> Vector2
    # Unit vector pointing FROM the scene TOWARD the light. For planet_ground's sun_dir.

static func shadow_dir() -> Vector2
    # Unit vector shadows are cast along = -light_dir(). For building_shadow's sun_dir,
    # BuildingShadow, AsteroidShadowRig. See §1.1 — these two are NOT interchangeable.

static func planetkit_light_origin(radius: float) -> Vector2
    # UV-space point for a PlanetKit set_light() / light_origin uniform.

static func apply_to_planetkit(node: Node, radius: float) -> void
    # Calls node.set_light(planetkit_light_origin(radius)) when the method exists. 13 kit
    # scenes expose set_light; this is the single call site for all of them. NOTE: 4 of the
    # 13 (Planet, Star, Galaxy, BlackHole) take `_pos` and no-op, so 9 actually respond —
    # the helper is harmlessly inert on the other 4.
```

### Call sites to convert

| file | change |
|---|---|
| `scripts/effects/building_shadow.gd` | `DEFAULTS.sun_dir` → `SceneLight.shadow_dir()` (no visible change — already 225°). `DEFAULTS` is a `const`, so the direction can't live in it; drop the key and inject at merge time in `attach`/`apply_params`. |
| `graphics/building_shadow.gdshader` | comment-only: `:14`, `:28`, `:66` say "light direction"; the code means shadow direction (§1.1) |
| `scripts/parallax/asteroid_shadow_rig.gd` | `SHADOW_DIR` → `SceneLight.shadow_dir()` — **visible change**, ~24° swing on ship shadows |
| `scripts/parallax/flyover_backdrop.gd` `:34` | its own `SHADOW_DIR` copy → same call, same swing — **convert with the rig or they drift** |
| `scripts/parallax/flyover_backdrop.gd` `:342` | `sun_dir` → `SceneLight.light_dir()` (**not** `shadow_dir` — §1.1) — **visible change, ~180°**: the flyover ground currently lights from ~41° |
| `scripts/parallax/layer_planet.gd` ×3 | `set_light(Vector2(0.0, 0.5))` → `SceneLight.apply_to_planetkit(p, RADIUS_PLANET)` — **visible change** if canonical ≠ 180° |
| `scripts/screens/sector_map_v3.gd` ×2 | same, map bodies |
| `scripts/dev/sector_map_v3.gd` ×4 | same, dev copy — convert together or it drifts |
| `scripts/parallax/asteroid_bake_cache.gd` | hardcoded `deg_to_rad(225.0)` → `SceneLight.DEFAULT_AZIMUTH_DEG` — the **constant**, not `azimuth_deg()`, per §5 option 1 |
| `scripts/enemies/asteroid_stronghold.gd` | `build_rock_visual` — currently relies on the shader default; make it explicit at `RADIUS_PLANETKIT_DEFAULT` (see radius note below) |
| `scripts/dev/asteroid_lab.gd` | keep its live `light_ang` slider, but seed it from `SceneLight.azimuth_deg()` |
| `scripts/dev/shader_lab.gd` `:270` | Building Shadow's `sun_angle_deg` default is **250**, ~205° from the shipped `BuildingShadow.DEFAULTS` 45° — the lab that produced the shipped tune no longer opens on it (saved tuner JSON masks this locally; a fresh checkout doesn't, and Copy→bake would ship the drift). Seed from `SceneLight`, converting into **shadow-direction space** per §1.1. Its other knobs in that block also default to the shader's uniform values rather than `BuildingShadow.DEFAULTS` — worth reconciling in the same pass. |
| `scripts/effects/shadow_fx.gd`, `scripts/effects/parallax_shadow.gd` | dormant (§1) — no change now; wire to `SceneLight.shadow_dir()` if they are ever re-enabled |
| starbase structural shadows | nothing to convert — no starbase-local light constant exists; it inherits whatever `BuildingShadow` uses (`starbase_assault_design_2026-07-28.md` §5.2) |

**Radius note (out of scope, worth recording):** baked rocks use radius `0.45` while live rocks — both
the loose `layer_stellar` ones and the stronghold rock — use the kit default `0.1556`. That is a
pre-existing terminator-softness mismatch between baked and live rocks, independent of azimuth.
Preserve each one's current radius here so L1 stays a true no-op; decide the look separately.

---

## 3. Which azimuth should win — DECIDED: 225°

**Roman chose 225° (up-left), 2026-07-28.** It is `SceneLight.DEFAULT_AZIMUTH_DEG`; the rest of this
section is the reasoning, kept for the record.

**Recommend 225° (up-left, 45°).** It's PlanetKit's own shipped default, it's what the baked rocks
and every building shadow already use, and a 45° oblique light is what reads best for top-down pixel
art — it's why `BuildingShadow` was tuned there. Cost: the backdrop planet and the sector-map bodies
visibly re-light from due-left to up-left.

The strongest argument is that **225° is not a new convention — it's what the code does when nobody
overrides it.** Every PixelPlanets shader ships `uniform vec2 light_origin = vec2(0.39, 0.39)`, i.e.
225°, without exception. The 180° rows in §1 exist solely because of five explicit
`set_light(Vector2(0.0, 0.5))` calls. Picking 225° is mostly *deleting overrides*, not imposing a
choice.

**Alternative: 180° (due left).** Lowest visible churn on the most prominent object, since the
backdrop planet keeps its current look. Cost: every building shadow and baked rock swings 45°, every
kit default has to be explicitly overridden forever, and a due-left light on a top-down deck casts
shadows straight sideways, which reads flatter.

Either way **`AsteroidShadowRig` (and the flyover's copy of it, and the flyover ground) move** —
none of them match either candidate today.

---

## 4. Star-reactive lighting (the reason for the SSOT)

Once everything derives from `SceneLight.azimuth_deg()`, making the light follow the star is a
change in exactly one function.

`stellar_gameplay.gd` already stages the star and every POI along the row — the star sits at frac
0.0 and each body carries its `pos_x` fraction (`_build_row_system`). So a node's angle to its star
is already derivable data:

```gdscript
static func azimuth_for_stellar(stellar: Dictionary) -> float
```

### What the geometry actually gives — and why the rule is a bounded swing

Measured from `backdrop_coordinator._spawn_system`, not assumed. The star is staged at
`center_x = SYS_X_MIN` (40.0) for **every** level — frac 0.0 pins it to the left edge — and its
*size* is what varies: `scale = intrinsic × exp(-5 × current_frac)`. So from the playfield centre
(240, 135) the star reads roughly:

- **at the star** (frac→0) — huge, low on the left → azimuth ≈ **176°**, near due-left
- **out at the rim** (frac→1) — a 2px dot high on the left → azimuth ≈ **212°**, up-left

So the honest screen-derived range is **~176°–212°** — it never reaches 225°, and most of it is the
flat due-left read §3 deliberately moved away from. Following it literally would undo that decision
one level after it was made.

**The rule as built:** take the same signal (`system_frac` — how far along the row the node sits)
and drive a swing **centred on canonical** instead:

```
azimuth = DEFAULT_AZIMUTH_DEG + lerp(-STAR_SWING_DEG, +STAR_SWING_DEG, system_frac)
```

At `STAR_SWING_DEG = 18°` that is **207° near the star → 225° mid-row → 243° at the rim/boss**. The
direction of travel matches the real geometry (further out ⇒ the sun rakes further over), every
level stays obliquely lit, and the whole thing is one constant to retune. `STAR_SWING_DEG = 0.0`
gives a fixed sun; raising it approaches the literal reading.

`system_frac` is written by `stellar_gameplay.gd` in both `compute_poi_stellar` (from `pos_x`) and
`compute_boss_stellar` (1.0 — bosses sit at the row endpoint). It is a pure float, so it consumes no
`deco_rng` and cannot shift the map/combat planet-pick lockstep. Dicts without it —
`StellarComposer`'s random dev compositions, menus, labs, and saved runs from before this landed —
fall back to canonical.

### Where it is published

`BackdropCoordinator._populate()`, at the very top, before the flyover branch returns. That is the
single funnel every backdrop host goes through (combat, signal events, dev labs, capture tools), and
critically it runs *before* the things that sample the light are built — the flyover ground's
`sun_dir`, every PlanetKit body's `light_origin`, the shadow rig. Labs injecting a `stellar_override`
get a consistent sun for free.

`SceneTransition._run` calls `reset_level_azimuth()` at each scene hop, next to the existing stray-
actor sweep, so the last combat's angle can't bleed into the outpost / summaries / sector map; any
scene with a backdrop immediately republishes its own.

resolved **once at level start** and pushed into `SceneLight.set_level_azimuth_deg()`, with
`azimuth_deg()` reading back the cached value.

*(The value is cached rather than re-read from `Run` meta on every call because per-frame consumers —
`AsteroidShadowRig` hits `shadow_dir()` each frame — would otherwise pay a `/root/Run` lookup per
frame.)*

**Contract: azimuth is constant for the duration of a level.** That's deliberate, and it's what
makes the whole thing cheap:

- `BuildingShadow` applies its params at attach time, so a mid-level change wouldn't reach shadows
  already attached without a re-apply pass.
- `AsteroidShadowRig` reads its direction per frame, so it *would* follow — producing the worst
  outcome, buildings and ships lit from different suns while the level runs.

A per-level constant gives Roman the thing he actually asked for (move the light, everything plays
along; light varies by where you are in the system) without any live-update machinery.

---

## 5. Constraint: baked atlases can't follow

`asteroid_bake_cache.gd` bakes lighting **into a sprite atlas**. The light is in the pixels, so
baked rocks cannot react to a per-level azimuth for free. Three options, in preference order:

1. **Baked rocks stay canonical.** Only live-shader bodies (planets, stronghold rocks, shadows)
   react. Cheapest; the cost is that decorative background rocks are lit from the canonical angle
   while the foreground reacts. At parallax distance this is unlikely to read as wrong.
2. **Azimuth in the bake key.** Correct, but multiplies atlas count and bake time by the number of
   distinct azimuths a run can produce.
3. **Quantize azimuth** to 4–8 buckets so the bake cost is bounded, accepting coarser reactivity.

Recommend (1) until star-reactive lighting is actually built — it costs nothing now and doesn't
foreclose the others. Concretely that means `asteroid_bake_cache.gd` reads
`SceneLight.DEFAULT_AZIMUTH_DEG` (the constant), **not** `SceneLight.azimuth_deg()` (which L3 makes
per-level) — see the §2 table row.

---

## 6. Sequencing

This is independent of the starbase work and can land before, after, or alongside it. It is *not* a
prerequisite: the starbase structural shadows just need `BuildingShadow`'s 45°, which they can read
directly today and switch to `SceneLight.shadow_dir()` whenever this lands.

Suggested order:

- **L1 — DONE 2026-07-28.** Module + no-op conversions. Add `scene_light.gd` at 225°; convert `BuildingShadow`, the
  baked-rock bake, and the stronghold rock; fix the `building_shadow.gdshader` comments (§1.1) so
  nothing downstream inherits the wrong convention. Zero visible change — pure plumbing, safe to
  verify. Nothing to do for the starbase: it has no light constant of its own and inherits
  `BuildingShadow`.
- **L2 — DONE 2026-07-28, UNPLAYTESTED.** The visible moves; three, not two: (a) `AsteroidShadowRig`
  **and** the flyover's duplicate `SHADOW_DIR` — ship shadows swing ~24°; (b) the planet/map
  `set_light` call sites (`layer_planet.gd` ×3, `screens/sector_map_v3.gd` ×2,
  `dev/sector_map_v3.gd` ×4) — 180° → 225°, a pure rotation on the same radius-0.5 terminator
  circle; (c) the flyover ground's `sun_dir` — ~41° → 225°, the largest single re-light in the pass.
  `planet_ground.gdshader`'s uniform default moved to canonical too, so nothing that forgets to set
  it drifts back. Dev labs now derive: `asteroid_lab`'s `light_ang` seeds from
  `SceneLight.azimuth_deg()`, and Shader Lab's Building Shadow tab seeds `sun_angle_deg` from
  `shadow_dir()` — its whole knob block had drifted to the raw shader uniform defaults and was
  realigned to `BuildingShadow.DEFAULTS`, so Copy→bake can't silently regress the shipped tune.
  **What to look at first:** a flyover planet-POI combat (the biggest change), then the sector map,
  then ship shadows over a rock field.
- **L3 — DONE 2026-07-28, UNPLAYTESTED.** `azimuth_for_stellar` + `system_frac` from
  `stellar_gameplay.gd` + the publish in `BackdropCoordinator._populate` + the reset in
  `SceneTransition._run`. Levels now light at 207°–243° by position in the system. **The one knob to
  judge is `SceneLight.STAR_SWING_DEG` (18°)** — it is the whole design decision in a single
  constant; 0.0 reverts to a fixed canonical sun.
