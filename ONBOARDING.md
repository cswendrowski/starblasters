# Starblaster — Human Dev Onboarding

A pragmatic guide for getting productive in this repo. Pairs with `CLAUDE.md` (which targets AI agents but is also the most up-to-date architecture reference — read it).

## What this project is

A Godot 4 top-down vertical shmup, written in GDScript. Started life as the kidscancode "Classic Shmup" tutorial and was rebuilt against the **Starblaster** design doc: a roguelite with a branching sector map, slotted parts, Mk.1–9 upgrade scaling, three bosses (Commander / Reaver / Sentinel), and procedural hazard levels (minefield, asteroid field).

Ships to itch.io as a Web (HTML5) build. No Steam/desktop release pipeline today.

## Setup

1. **Install Godot 4.3 Mono** — this is the editor. Mono is required because `project.godot` declares `assembly_name="Classic Shmup"` (C# is present even if you never touch it). Put `godot` on your PATH.
2. **Install Godot 4.4.1 standalone (non-Mono)** — used only by the publish pipeline. Mono can't export to Web (silent exit 5). The publish script pins the standalone path.
3. **Install `butler`** (itch.io CLI) and log in if you'll be publishing.
4. **Install ffmpeg** (on PATH) if you'll iterate on visual effects — the capture scripts pipe PNG frames into GIFs.
5. Open `project.godot` in the 4.3 Mono editor. The Godot MCP addon is enabled but optional — it just lets AI agents poke the live editor over a WebSocket.

Renderer is `gl_compatibility` (for Web). Internal viewport is **480×270** with a **216×270 centered playfield band** — all gameplay math is in those coords, the side gutters are HUD/glass. (CLAUDE.md still says 320×400 in places; the project switched to a wider letterbox on the `horizontal-rework` branch.)

## Repo layout

```
scenes/             *.tscn — every screen, ship, projectile, FX
  dev/              dev menu sub-scenes (tuners, labs, sizers)
scripts/
  main.gd           combat scene controller
  player.gd         player ship (stat-driven, parts populate it)
  boss.gd           boss base
  run_state.gd      Run autoload (persistent run state)
  enemies/
    enemy_base.gd     Area2D base for everything in `enemies` group
    enemy_core.gd     pattern-driven layer (movement Resource + shoot Resource)
    patterns/         movement Resources
    shoot_patterns/   fire Resources
  projectiles/      base_bullet.gd, base_missile.gd + subclasses
  effects/          static FX helpers (hit_flash, explosion, debris, …)
  levels/           wave_generator(_v2), levels_v2 (hazards), director
  parts/            slotted upgrade Parts (Mk.1–9 scaling)
  weapons/          SlotTypes, weapon Parts
  dev/              dev menu pages (tuners, ship sizer, …)
  playfield.gd      bounds constants — import this, don't hardcode
graphics/           sprite assets (some from third-party Mini Pixel Pack 3)
tools/              publish, parse_check, capture scripts, smoke harness
captures/           gitignored — capture script output
addons/
  godot_mcp/        Godot MCP addon (optional)
```

`.uid` files sit next to every `.gd`/`.gdshader` — Godot-generated resource UIDs. **Commit them, never edit them.** `.tmp` files are editor autosave leftovers — ignore.

## Boot path

`main_menu.tscn` (main scene) → either

- **Start Run** → `sector_map_v2.tscn` → node click goes to `main.tscn` (combat), `outpost.tscn`, `signal_event.tscn`, etc. Combat ends → `cleared_summary.tscn` → back to sector map.
- **Dev Menu** → grid of test scenes (Wave Tester, Movement Lab, Boss Fight, UI Designer, Ship Sizer, Parallax Tuner, Asteroid Lab, Test Hazard, Hangar, …).

Autoloads (`/root/*`): `Run`, `Dbg`, `Music`, `Settings`. `Run` is the one you'll touch most — it holds bounty, hull/shield, the loadout snapshot, the cached sector map, current node, and `set_meta(...)` one-shot config that combat/wave-gen consume.

## How the systems fit

- **Combat (`scripts/main.gd`)** picks a `LevelData` builder based on `Run.current_node_type` or a meta override: `WaveGen.build` (production), `WaveGeneratorV2.build_combat` (dev tester), or `Levels.build_*_level` (hazards).
- **WaveDirector (`scripts/levels/director.gd`)** walks the `WaveSpec`s, spawns enemies, emits `enemy_died`, `wave_started`, `level_cleared`. `level_cleared` runs the outro tween → cleared_summary.
- **Enemies** are `EnemyBase` (Area2D, in `enemies` group). Most are `enemy_core` with a movement Resource + shoot Resource. Bespoke logic (bomber, bulwark v2) subclasses `enemy_base` directly. Custom enemies expose `hull`/`max_hull` shim properties + `hull_changed` signal so damage tells (engine_torch, smoke trail) reuse the same plumbing as the player.
- **Player** is stat-driven from Parts via `PlayerLoadout`. Stats start at zero; equipping Parts mutates them through `apply(ship)`/`unapply(ship)`. Shield is a **charge pool** (per-hit, brief i-frames, then bleeds to hull). Same mechanic on shielded enemies.
- **Projectiles** extend `base_bullet.gd` or `base_missile.gd`. **Spawn under `get_tree().root`**, never under the shooter — the shooter dies and you don't want bullets dying with it.
- **Effects** are static helpers: `ExplosionFx.play(pos)`, `HitFlashFx.flash(node, kind)`, `ShadowFx.attach_shadow(spr)`, etc.

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

Two Godot binaries, two parsers, and that's where most publish disasters come from.

1. **Smoke test against 4.4.1 standalone**, not just the 4.3 editor. The editor will happily parse things 4.4.1 rejects (duplicate `var` shadows, walrus on untyped array indexing). `tools/parse_check.ps1` runs every user-reachable scene through 4.4.1.
2. **Commit before you publish.** Each release is a commit on `main`, so `git bisect` lands on a published build.
3. **Run `tools/publish.ps1 -Version "0.1.NN"`.** It bumps `config/version` in `project.godot`, runs the parse check as a hard gate, exports via standalone 4.4.1, validates the `.pck` mtime, and calls `butler push`. **Never `butler push` directly.** Never `--no-verify`.
4. Quick post-publish check: open the itch page, hard-refresh, confirm version string in the corner matches what you bumped to.

The pre-built `Classic Shmup.console.exe` / `*.pck` / `shmup-*.zip` at the repo root are publish *outputs*, not inputs. Don't commit changes to them by hand.

## Debugging tips

- **Headless smoke (4.3 mono)**: `godot --path . --headless --quit-after 2` — boots autoloads + main scene, surfaces parser errors and missing-resource errors fast.
- **Full parse check (4.4.1)**: `tools/parse_check.ps1` — catches Web-export-only parser errors.
- **`DirAccess.open("res://...")` does not work in Web builds** at runtime. Use a hardcoded const manifest if you need to enumerate assets.
- **Bullets vanish on enemy death?** They're parented to the enemy. Reparent to `get_tree().root`.
- **Shader on Web looks wrong?** `gl_compatibility` is a subset of GL ES 3.0. Some Forward+ features silently no-op. Test on Web before assuming it's fine.
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
