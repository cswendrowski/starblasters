# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 2D top-down vertical shmup (GDScript). Originated from the kidscancode "Godot 101: Classic Shmup" tutorial; rebuilt against the Starblaster design doc as a roguelite shmup with branching sector map, slotted parts, and Mk.1–9 upgrade scaling. Renderer: `gl_compatibility`. **Internal viewport 320×400 with `stretch/mode = viewport` (2× display = 640×800).** All position/size math is in 320×400 coords.

## Engine versions (important — they parse differently)

The project uses **two** Godot binaries:

- **Godot 4.3 Mono** — the editor, used for day-to-day work. Mono is required because the project ships C# (`assembly_name="Classic Shmup"` per project.godot). Mono **cannot export to Web** — it fails silently with exit 5.
- **Godot 4.4.1 standalone (non-Mono)** — used only for the web export. 4.4.1's GDScript parser is **stricter** than 4.3's: rejects duplicate `var` shadows, rejects walrus `:=` on untyped array indexing. **A clean editor smoke test does NOT guarantee a working web build.** Always run `tools/parse_check.ps1` before publishing — it's wired into `tools/publish.ps1` as a hard gate.

## Running / building

No CLI build for the editor side — open `project.godot` in Godot 4.3 Mono.

- Headless smoke (4.3 mono, on PATH as `godot`): `godot --path . --headless --quit-after 2`
- Full parse check (4.4.1 standalone, every user-reachable scene): `tools/parse_check.ps1`
- Publish to itch (web): `tools/publish.ps1 -Version "0.1.NN"` — bumps `config/version`, runs parse_check as a gate, exports via standalone 4.4.1, mtime-validates the pck, then `butler push`. **Never `butler push` directly — always go through publish.ps1 with explicit version bump.** Don't push without explicit user confirmation.
- Pre-built artifacts (`Classic Shmup.console.exe`, `*.pck`, `shmup-*.zip`) at repo root are release outputs, not inputs.
- No test framework. No lint step.

## Visual capture pipeline

For iterating on visual mechanics (shaders, particle FX, drop shadows, projectile feel), write a one-shot `tools/capture_<mechanic>.gd` (SceneTree script) + `.ps1` wrapper that runs ffmpeg to a GIF. Pattern is proven for `capture_boss_blackhole`, `capture_debris`, `capture_engine_torch`, etc. **Always Read the captured PNG frames to verify the visual before claiming a fix landed — a clean smoke test only verifies the code parsed, not that the visual is correct.**

## Input map

Defined in `project.godot` under `[input]`:
- Movement: `left`/`right`/`up`/`down` (WASD + arrows)
- `shoot` (Space), `shoot2` (G), `shoot_nose` (Shift)
- `weapon_previous` (Q), `weapon_next` (E)

## Autoloads (`/root/...`)

- `Run` (`scripts/run_state.gd`) — persistent run state: bounty, hull/shield, loadout snapshot, sector_map_cache, current_node_id/type, current_hazard_subtype, sectors_cleared, run_seed. `Run.new_run()` resets. Dev menu and signal events stash one-shot config via `Run.set_meta(...)` (e.g. `wave_v2_knobs`, `forced_boss_scene`, `minefield_mine_type`) consumed by `main.gd` / wave generator on combat start.
- `Dbg` — debug helpers
- `Music` — context-aware BGM (`set_context("menu"|"combat"|"boss"|"sector")`)
- `Settings` — persisted user prefs

## Architecture

### Scene flow
`main_menu.tscn` (main scene) → `main.tscn` (combat) ↔ `sector_map_v2.tscn` → `outpost.tscn` / `signal_event.tscn` / `cleared_summary.tscn` / `run_summary.tscn`. Sector map is V2 (a 12-row grid with forward-only edges; `_strip_backward_edges` enforces the invariant after generation AND after cache restore).

### Combat flow (`scripts/main.gd`)
`main.gd::new_game()` looks at `Run.current_node_type` (or `wave_v2_knobs` meta) and builds a `LevelData` via either:
- `WaveGen.build(sector_depth, level_index, is_boss)` — `scripts/levels/wave_generator.gd`, the dynamic generator used in production.
- `WaveGeneratorV2.build_combat(sector_idx, knobs)` — `scripts/levels/wave_generator_v2.gd`, used by the Wave Tester dev menu. Knobs auto-derive from `sector_depth`: more waves, more density, deeper tier pool as depth climbs. Includes a rare bomber-wing event (`_pending_wings` static registry).
- `Levels.build_minefield_level()` / `build_asteroid_field_level()` — `scripts/levels/levels_v2.gd`, the live hazard builders. Minefield reads `Run.minefield_mine_type` meta if the dev tester forced a composition.

`scripts/levels/director.gd` (instanced as `WaveDirector` under Main) walks the level's `WaveSpec`s and spawns enemies. Emits `enemy_died(value)`, `wave_started(i, total)`, `level_cleared`. `level_cleared` triggers `_run_outro()`: exit thruster SFX, player fly-out tween, wipe-to-black, mount `ClearedSummaryScene`.

### Enemies (`scripts/enemies/`)
- `enemy_base.gd` (extends `Area2D`, `class_name EnemyBase`) — base for everything in the `enemies` group. Provides `health`/`max_health`/`take_hit(damage)`/`explode()`/`died(value)`, automatic engine flame + parallax shadow + damage overlay shader for ships (`auto_rotate` gates these), debris spawn on death (`_spawn_debris`), offscreen cleanup via `offscreen_mode` enum.
- `enemy_core.gd` — pattern-driven layer on top of EnemyBase. Adds `movement: Resource` + `shoot_pattern: Resource` slots and the legacy "anchor follow" fallback.
- `patterns/` — movement Resources (`straight_down`, `s_curve`, `loiter`, `boss_sweep`, `top_dive`, `side_cut`, `advance_retreat`, `beeline_player`, `slow_advance`, `omni_thrust`, `inertial_thrust`, `jet_*`). Subclass `movement_pattern.gd`; override `compute_step(enemy, delta) -> Vector2`.
- `shoot_patterns/` — fire Resources (`single_shot`, `aimed_fire`, `spread_shot`, etc.).
- Custom enemies that need bespoke `_process` logic (bomber, bulwark v2) extend `enemy_base.gd` directly. They expose `hull` / `max_hull` shim properties and a `hull_changed(max, current)` signal so player-side damage tells (engine_torch, damage_smoke_trail) can attach to them too.

### Bosses (`scripts/boss.gd`, `scripts/enemies/boss_reaver.gd`, `boss_sentinel.gd`)
Three bosses (Commander/Reaver/Sentinel) share `boss.gd` as base. Each sets stats directly in `_ready()` before `super._ready()` — never via the `<= 0 ? default` pattern (caused 1-HP bug). Boss attack: charge-fire-detonate black hole (`_run_black_hole_sequence`) — small hole tracks boss during 2.5s charge with boss `_charging = true` halting shoot timer + slowing sweep, fires straight down to player Y, detonates with concentric scale tween + pull activation. `boss_sweep.gd` X-axis uses `sin³(t)` easing so direction reversals aren't stark.

### Player (`scripts/player.gd`, part-driven stats)
All stats start at zero and are populated by **Parts** equipped through `PlayerLoadout`. See `scripts/weapons/SlotTypes.gd` for the 10-slot layout, `scripts/parts/*` for parts. Shield is a CHARGE pool — each hit consumes one charge with brief i-frames regardless of damage; once empty, damage bleeds to hull. **Same mechanic on all shielded enemies** (bulwark, bomber, mine_shielded). When hull ≤ 50%, `engine_torch` (procedural fire shader at the engine pixel) + `damage_smoke_trail` (textured Line2D with drift) kick in. `take_damage()` applies sector damage scaling `× (1 + 0.05 × sectors_cleared)` before shield/armor math.

### Projectiles (`scripts/projectiles/`)
All projectiles extend `base_bullet.gd` (player bullets, enemy bullets, `bullet_minigun`) or `base_missile.gd` (player + enemy missiles). Both have offscreen cleanup. **Spawn bullets as children of `get_tree().root`, never the player or enemy** — so they survive the spawner's `queue_free`.

### Backdrop (`scripts/galaxy_backdrop.gd`)
Parallax stack: deep-sky base → starfield foundation → nebula → planet (one stellar body per level) → asteroids (deep/mid/near bands) → warp streaks → anchor tint → vignette. Celestial pick is **weighted** (`_weighted_celestial_pick`): 7% BlackHole, 3% Galaxy, 40% Star, 50% globe planet (split across 6 variants). Globe planets can spawn moons; stars can be binary (`_spawn_companions`). Mine-hazard levels also drop decorative background mines via `_spawn_background_mines` (no collision, multiply-blend at 50% black).

### Effects (`scripts/effects/`)
Static helpers — most are called as `Cls.method(...)` (no instance needed): `hit_flash_fx.flash(node, kind)`, `shadow_fx.attach_shadow(spr)`, `parallax_shadow.attach(node)`, `explosion_fx.play(pos, scale)` or `.burst(pos, count, jitter, stagger)` for multi-blast, `impact_fx.spawn(parent, pos, color, kind)`, `burn_fx.apply_burn(spr, dur)`, `enemy_engine_fx.attach(enemy, tint, scale)`, `shield_sfx.play_hit/play_break(parent, pos)`. Damage tell pair: `engine_torch.attach_to_player(host, nozzle_offset)` + `damage_smoke_trail.new()` with `emit_local` set — both gate on `hull_changed` and a 50%-hull threshold.

### Dev menu (`scripts/dev_menu.gd`, reachable from main menu)
Movement Test, Movement Lab, **Wave Tester** (V2 with sector+depth sliders), Shipyard, Parallax Tuner, **Asteroid Lab**, Test Bed, **Test Hazard** (Minefield with composition sub-modal / Asteroid Field), **Boss Fight** (pick from Commander/Reaver/Sentinel — sets `Run.forced_boss_scene`, consumed by `wave_generator._pick_boss`), Hangar.

## Conventions worth knowing

- **Hitboxes**: enemy CollisionShape2D = sprite size exactly (no inset). Player hitbox = sprite size − 2-4 px (gives wiggle-room for close calls). Difficulty goes through HP/damage/spawn rate, never via stealth-shrunk hitboxes.
- **Explosions**: always native 1× scale. Big enemies get MORE blasts (`ExplosionFx.burst(pos, count, jitter, stagger)`) with random jitter, not stretched sprites. Same rule for debris — count scales with enemy size, piece scale is fixed at 1×.
- **All ships moving forward**: the game's fiction is that the player races forward (up) and enemies fly down toward them. Stationary-looking objects are actively propelling themselves. Death VFX (debris, falling hulks) should immediately drift downward from frame 0 — never "freeze then fall."
- `.uid` files next to every `.gd`/`.gdshader` are Godot-generated resource UIDs — commit them; never edit by hand.
- `.tmp` files in `scenes/player/` and the repo root are Godot editor autosave leftovers — safe to ignore, do not treat as source.
- Sprite assets come from "Mini Pixel Pack 3" (third-party) and `graphics/`. Don't relocate without updating `.tscn` resource paths.
- `default_texture_filter=0` (nearest) is intentional for the pixel-art look.
- When adding a new Part: extend `Part`, set `slot_type` in `_init`, override `apply(ship)` (additive + record delta) and `unapply(ship)` (reverse). Register in `PartFactory` for starting/shop pools.

## Godot MCP integration

`addons/godot_mcp/` (ee0pdt/Godot-MCP) is enabled. With the Godot editor open and the addon's WebSocket server running on port 9080, Claude Code can read/edit scripts and scene trees live. Bridge binary: `F:\Programming\Git\Godot-MCP\server\dist\index.js`. Editing `.tscn` files on disk while the editor has them open will prompt for a reload — accept it.
