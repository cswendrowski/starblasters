# Starblaster — Human Dev Onboarding

A pragmatic guide for getting productive in this repo. Pairs with `CLAUDE.md` (which targets AI agents but is also the most up-to-date architecture reference — read it).

## What this project is

A Godot 4 top-down vertical shmup, written in GDScript. Started life as the kidscancode "Classic Shmup" tutorial and was rebuilt against the **Starblaster** design doc: a roguelite with a branching sector map, slotted parts, Mk.1–9 upgrade scaling, a growing boss roster (see `scripts/enemies/boss_*.gd`), and procedural hazard levels (minefield, asteroid field).

Ships to itch.io as a Windows executable. Web/HTML5 export pipeline retired 2026-06-10.

## Setup

1. **Install Godot 4.6.3 standalone (non-Mono)** — a single binary serves as both the editor and the Web exporter. (The repo was consolidated off a 4.3-Mono-editor + 4.4.1-standalone-exporter split on 2026-05-26; the project never used C#.) The publish/parse scripts pin its absolute path — see `tools/publish.ps1` and `tools/parse_check.ps1`.
2. **Install `butler`** (itch.io CLI) and `butler login` if you'll be publishing.
3. **Install ffmpeg** (on PATH) if you'll iterate on visual effects — the capture scripts pipe PNG frames into GIFs.
4. Open `project.godot` in the 4.6.3 editor. The Godot MCP addon is enabled but optional — it just lets AI agents poke the live editor over a WebSocket.

Renderer is `forward_plus` (see `project.godot:20` for the feature flag). Internal viewport is **480×270** with a **216×270 centered playfield band** — all gameplay math is in those coords, the side gutters are HUD/glass.

## Repo layout

```
scenes/             *.tscn — every screen, ship, projectile, FX
  dev/              dev menu sub-scenes (tuners, labs, sizers)
scripts/
  autoload/         Run, Dbg, Music, Settings
  game/             main.gd (combat), player.gd, player_loadout.gd
  enemies/          enemy_base.gd, enemy_core.gd, bosses/, patterns/, shoot_patterns/
  levels/           director.gd, wave_generator.gd, factions.gd
  projectiles/      base_bullet.gd, base_missile.gd + subclasses
  effects/          static FX helpers (hit_flash, explosion, debris, …)
  parts/            slotted upgrade Parts (Mk.1–9 scaling)
  weapons/          SlotTypes, weapon Parts
  hud/              UI (overlay, hud.gd, etc.)
  screens/          scene controllers (outpost.gd, sector_map_v3.gd, etc.)
  parallax/         backdrop, layer_planet.gd, etc.
  systems/          playfield.gd, sector_map_route.gd, scene_transition.gd
  dev/              dev menu pages (tuners, ship sizer, …)
  strings/          strings.gd (localization)
  ui/               UI theme and helpers
graphics/           sprite assets (some from third-party Mini Pixel Pack 3)
tools/              publish, parse_check, capture scripts, smoke harness
captures/           gitignored — capture script output
addons/
  godot_mcp/        Godot MCP addon (optional)
```

`.uid` files sit next to every `.gd`/`.gdshader` — Godot-generated resource UIDs. **Commit them, never edit them.** `.tmp` files are editor autosave leftovers — ignore.

## Boot path

`main_menu.tscn` (main scene, set in `project.godot:19`) → either:

- **Start Run** → `sector_map_hd.tscn` (wraps `sector_map_v3.tscn`) → node click goes to `main.tscn` (combat), `outpost.tscn`, `signal_event.tscn`, etc. Combat ends → `cleared_summary.tscn` → back to sector map. Outpost is a **persistent hub button** on the map (available anytime, doesn't advance progress).
- **Dev Menu** → grid of test scenes. See `scripts/dev/dev_menu.gd` for the current button list (list drifts; don't hardcode expectations).

Autoloads (`/root/*`): `Run`, `Dbg`, `Music`, `Settings` (registered in `project.godot:26–29`). `Run` is the one you'll touch most — it holds bounty, hull/shield, the loadout snapshot, the cached sector map, current node, and `set_meta(...)` one-shot config that combat/wave-gen consume.

## How the systems fit

- **Combat (`scripts/game/main.gd`)** picks a `LevelData` builder based on `Run.current_node_type` or a meta override: `WaveGen.build` (production waves), or `Levels.build_minefield/asteroid_field_level` (hazards).
- **Director (`scripts/levels/director.gd`)** walks the wave definitions, spawns enemies, emits `enemy_died`, `enemy_spawned`, `wave_started`, `level_cleared`. `level_cleared` runs the outro tween → `cleared_summary.tscn`.
- **Enemies** are `EnemyBase` (Area2D, in `enemies` group). Most use `enemy_core` with a `movement` Resource + `shoot_pattern` Resource. Bespoke logic (custom HP/behavior) subclasses `enemy_base` directly. Bosses live in `scripts/enemies/bosses/` and `scenes/enemies/bosses/`.
- **Player** is stat-driven from Parts via `PlayerLoadout` (`scripts/weapons/loadout.gd`). Stats start at zero; equipping Parts mutates them through `apply(ship)`/`unapply(ship)`. Shield is a **charge pool** (per-hit, brief i-frames, then bleeds to hull). Same mechanic on shielded enemies.
- **Projectiles** extend `base_bullet.gd` or `base_missile.gd` (`scripts/projectiles/`). **Spawn under `get_tree().root`**, never under the shooter — the shooter dies and you don't want bullets dying with it.
- **Effects** are static helpers in `scripts/effects/`: `ExplosionFx.play(pos)`, `HitFlashFx.flash(node, kind)`, `ShadowFx.attach_shadow(spr)`, etc.

## Adding things

**A new enemy variant (no new code)** → make a `.tres` for `enemy_core` with a movement + shoot pattern Resource. Hook into a `WaveSpec` in `wave_generator.gd` or a level builder.

**A new movement pattern** → subclass `scripts/enemies/patterns/movement_pattern.gd`, override `compute_step(enemy, delta) -> Vector2`. Use `Playfield.X_MIN/X_MAX` for bounds — never `get_viewport_rect()`.

**A new Part** → subclass `Part`, set `slot_type` in `_init`, override `apply(ship)` (additive, record delta) and `unapply(ship)` (reverse the delta). Register in `PartFactory` so it shows up in shop/start pools.

**A new visual effect** → write it in `scripts/effects/`. Then iterate on it via the capture pipeline.

**A new dev tuner** → follow `scripts/dev/parallax_tuner.gd` / `ui_designer.gd` / `ship_sizer.gd` as references. Left rail panel, knob rows (`Label | HSlider | SpinBox`), JSON save/load to `user://tuners/`, Esc-to-close. Add an entry to `scripts/dev_menu.gd`.

## Conventions that matter

- **Hitboxes**: enemy collision = sprite size exactly. Player collision = sprite size minus 2–4 px (forgiveness on close calls). Difficulty rides on HP/damage/spawn rate, not on shrinking hitboxes.
- **Explosions and debris**: native 1× scale always. Big enemies get *more* blasts (`ExplosionFx.burst`) with jitter, never stretched sprites.
- **All ships move forward**: player races up, enemies fly down. Death VFX must drift downward from frame 0 — no "freeze then fall."
- **Shadows**: oblique drop shadows go on ships and large projectiles (missiles, bombs) only. Never on small bullets.
- **No silent fallbacks**: if a bug is "X should not Y," grep for every path that does Y across base and subclasses. Delete the fallback, don't gate it.
- **Black hole is decorative**: the background black hole is pure visual flair. No gravity, no damage, no interaction.

## Workflow: iterating on enemies + waves

This is a data-first loop — author Resources in Godot's inspector, hit "Test Level" to play. No code edits required for new wave compositions or enemy stat tweaks.

**Tweak an enemy** (HP, bounty, speed, damage, hitbox, sprite):
- Open `scenes/enemies/enemy_<name>.tscn` in Godot.
- Edit `@export` vars on the root node in the inspector — `max_hull`, `bounty_value`, `movement` (a movement-pattern Resource), `shoot_pattern` (a shoot-pattern Resource), etc.
- Save. Changes apply on the next combat boot.

**Tweak a movement or shoot pattern** (S-curve amplitude, dive angle, fire interval):
- Patterns are `Resource` scripts under `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/`. Each has `@export` knobs.
- In Godot, FileSystem panel → right-click → New Resource → pick the pattern script. Save as `resources/patterns/my_pattern.tres`. Edit knobs in inspector.
- Drop the new `.tres` into an enemy's `movement` / `shoot_pattern` slot — or into a `wave_def.gd`'s `movement_override` / `shoot_pattern_override` slot (per-wave override).

**Compose a custom wave**:
- FileSystem → right-click → New Resource → `scripts/levels/wave_def.gd`. Save as `resources/waves/my_wave.tres`.
- Inspector fields: `enemy_scene` (drop in a `.tscn`), `count`, `spawn_interval`, `spawn_delay`, `formation`, `movement_override` (optional), `shoot_pattern_override` (optional), `max_health` (optional override), `bounty_value` (optional override), `silent` (skip the WAVE banner), `announce_text` (custom banner copy).

**Compose a level** (one or more waves played in order):
- New Resource → `scripts/levels/level_def.gd`. Save as `resources/levels/test_level.tres` *(this exact filename is what the dev menu loads)*.
- Drag your wave `.tres` files into the `waves` array in the inspector. Order = play order.

**Test it**:
- Run the project. Main menu → Dev Menu → **Test Level**.
- This loads `resources/levels/test_level.tres` and boots combat with it. Die or clear → back to menu → tweak the `.tres` → retry.
- The dev menu's existing **Wave Tester** is different — that drives the procedural generator with sector/depth knobs (no specific authored wave).

Examples to copy and mutate: `resources/waves/test_wave_darts.tres`, `resources/waves/test_wave_hoppers.tres`, `resources/levels/test_level.tres`.

## Workflow: when to use a tuner vs. ask Claude

Context is the scarce resource on Claude's side. The cheapest collaboration is the one where you iterate locally (eyes-on, sub-second feedback) and Claude only consumes the *result*. Use this matrix:

| Task | Where | Output → Claude |
|---|---|---|
| HUD layout, panel sizing, gutter widths | **UI Designer** tuner | hit "Copy GDScript", paste in chat |
| Ship/enemy sprite scale + facing previews | **Ship Sizer** tuner | "Copy GDScript", paste |
| Parallax layer brightness/contrast/speed/silhouette | **Parallax Tuner** | "Copy GDScript" or commit `user://tuners/parallax.json` and reference it |
| Wave count / density / tier ceiling per sector | **Wave Tester** | just play it — knobs are scoped to that run; ask Claude only if a value should become production default |
| Single enemy/part/maneuver `.tres` numbers | **Godot inspector** on the `.tres` | commit the `.tres` — Claude doesn't need to be involved at all |
| Maneuver pattern feel (S-curve amplitude, loiter timing) | **Movement Lab** + Godot inspector on the pattern Resource | commit the `.tres` |
| Asteroid density / drift / spawn rate | **Asteroid Lab** | (no export yet — describe the feel and Claude will tune) |
| Boss timing windows (charge / sweep / black-hole) | no tuner yet — Godot inspector on `scripts/boss*.gd` exports, or `.tres` if it's a Resource | commit |
| New Part / new movement pattern / new shoot pattern | code | ask Claude |
| New enemy variant (using existing patterns) | `.tres` in Godot editor | commit; ask Claude only to slot it into a wave |
| Visual effect / shader / particle FX | code + capture pipeline | ask Claude |
| Bug investigation, refactor, new system | code | ask Claude |

Rule of thumb: **if it's a number on something that already exists, you should be the one tuning it.** Bring Claude in when the number drives something structural (e.g. a Mk-scaling curve that needs a formula, not nine hand-typed values).

If you find yourself wanting a tuner for a 3+-knob system that doesn't have one, ask Claude to scaffold it — see `scripts/dev/parallax_tuner.gd` or `ui_designer.gd` as references. Each tuner gets Save / Load / Copy-GDScript at minimum.

## The capture pipeline (visual iteration)

For any visual mechanic — shader, particle FX, drop shadows, projectile feel — the loop is:

1. Write `tools/capture_<mechanic>.gd` (SceneTree script). Boot a minimal scene, exercise the mechanic deterministically (seeded RNG, fixed positions), screenshot the viewport into `captures/<mechanic>/frame_NNNN.png`, quit after N seconds.
2. Write `tools/capture_<mechanic>.ps1` to invoke it via headless Godot, then run ffmpeg over the PNGs to `captures/<mechanic>.gif`.
3. Run it, **look at the GIF or PNGs**, iterate.

A passing smoke test means the code parsed. It does **not** mean the visual is right. Look at the output.

## Releasing

One Godot binary (4.6.3 standalone) serves as both editor and exporter. Parse-check is a belt-and-braces gate (catches scripts that only resolve against the editor's class cache).

1. **Smoke test / parse check.** `tools/parse_check.ps1` runs every user-reachable scene through the same 4.6.3 binary the export uses.
2. **Commit before you publish.** Each release is a commit on `main`, so `git bisect` lands on a published build.
3. **Run `tools/publish.ps1 -Version "0.1.NN"`.** It bumps `config/version` in `project.godot`, runs the parse check as a hard gate, **exports the WINDOWS preset** to `../Starblaster_win/`, validates the `.exe` mtime advanced (catches a silent no-op), and calls `butler push` to `tikibones/starblaster:windows`. **Never `butler push` directly.** **Don't publish without explicit maintainer approval.**
4. Quick post-publish check: open the itch page, hard-refresh, confirm version string matches what you bumped to.

## Debugging tips

- **Headless smoke**: `godot --path . --headless --quit-after 2` — boots autoloads + main scene, surfaces parser errors and missing-resource errors fast.
- **Full parse check**: `tools/parse_check.ps1` — catches export-only parser errors.
- **`DirAccess.open("res://...")` fails in exported builds** at runtime (embedded `.pck`). Use a hardcoded const manifest if you need to enumerate assets.
- **Bullets vanish on enemy death?** They're parented to the enemy. Reparent to `get_tree().root`.
- **Shader looks wrong in-game?** Check the shader syntax against `forward_plus` specifics (not all Forward+ features are built-in; test in-editor before export).
- **Boss has 1 HP at fight start?** You used the `stat <= 0 ? default : stat` pattern in `_ready()` after `super._ready()` already ran. Set stats *before* `super._ready()`.
- **A new movement pattern lets enemies leave the playfield?** It's reading `get_viewport_rect()` instead of `Playfield.X_MIN/X_MAX`. The viewport is 480 wide; the playfield is 216 wide and centered.

## Working with AI agents in this repo

This project uses Claude Code + Godot MCP. If you're not interested in that side, skip this section.

- `CLAUDE.md` is the source of truth for architecture invariants — keep it current when you change something it documents.
- `.claude/agents/*.md` defines specialized subagents (capture-poster, smoke-runner, tuner-builder, design-reviewer, …). Each has a `model:` override pinned to the cheapest tier that's actually good enough.
- The MCP addon (`addons/godot_mcp/`) runs a WebSocket server on port 9080 when the editor is open, letting agents edit live scene trees. Editing a `.tscn` on disk while the editor has it open prompts a reload — accept it.

## Pointers

- Architecture invariants and current systems: `CLAUDE.md`
- Design doc: ask Roman
- Publish toolchain: `tools/publish.ps1`, `tools/parse_check.ps1`
- Reference tuner: `scripts/dev/parallax_tuner.gd`
- Reference capture script: `tools/capture_boss_blackhole.gd` + `.ps1`
