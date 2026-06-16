# File structure guide

How this project's files are organized + where new ones go. Companion to the architecture
tour in `docs/contributing/02-architecture.md` (that's *what the systems are*; this is
*where the files live*). Began 2026-06-14 as a staged reorg (change map:
`docs/archive/file_reorg_changemap_2026-06-14.md`).

## Principles
1. **Group by domain, not by type-at-root.** `scripts/` should not be a flat catch-all.
2. **Mirror `scripts/` ↔ `scenes/`** where a script backs a scene (e.g. `scripts/enemies/
   bosses/` ↔ `scenes/enemies/bosses/`).
3. **One root per asset class.** Sprites + shaders under `graphics/`, audio under `Sound/`
   (→ planned `assets/audio/`), data under `resources/` + `data/`.
4. **Commit `.uid`/`.import` sidecars; never hand-edit them.**

## `scripts/` layout (current)
- `autoload/` — the 4 singletons in `project.godot [autoload]`: run_state (Run), dbg (Dbg),
  music_manager (Music), settings (Settings).
- `game/` — core game loop: main (combat), player, ship.
- `effects/` — ALL visual/audio FX (explosions, trails, muzzle, shaders, sfx wrappers,
  burn/shadow/trail_fx). Static-helper classes called as `Cls.method(...)`.
- `enemies/` — `enemy_base.gd` + `enemy_core.gd` (the composed-enemy base); subdirs:
  `bosses/` (boss.gd + boss_*.gd + boss_base/phase), `core/` (universal chaff/elite),
  `factions/<faction>/` (faction-exclusive), `patterns/` (movement Resources),
  `shoot_patterns/` (weapon Resources), `components/` (EnemyComponent).
- `screens/` — player-facing scene scripts: main_menu, outpost, manage_ship, signal_event,
  cleared_summary, run_summary, run_history, sector_map_v3, sector_map_hd, credits,
  pause_menu, onboarding, enemy_codex.
- `systems/` — shared world/runtime systems: playfield, clarity, lanes, lane_traffic, zones,
  scene_transition(_overlay), sector_node, sector_map_route, black_hole, beat, Camera2D.
- `hud/` — in-combat HUD: ui.gd (the HUD/UI root) + widgets hud_light, hull_pips,
  shield_pips_hud, hologram_hud, score_counter, wave_banner.
- `strings/` — string/codex tables: strings, armory_strings, codex_strings, enemy_strings,
  sector_name_generator.
- `parts/` — Parts (slotted upgrades + weapons): Part subclasses + PartFactory/PartCatalog.
- `weapons/` — weapon plumbing: loadout, SlotTypes, WeaponStyle, enemy_bullet/rocket.
- `projectiles/` — base_bullet/base_missile + concrete projectile scripts.
- `levels/` — wave_generator, levels_v2, factions (the producer).
- `parallax/` — galaxy_backdrop (coordinator) + backdrop layers.
- `ui/` — shared UI framework: HdScreen, ui_theme, options_overlay, volume_slider.
- `dev/` — dev tools/screens (enemy_bench, combat_lab, smart_mount_lab, parallax_tuner,
  dev_menu, hangar, feature_showcase, debug_testbed, …).
- `player/` — player helper scripts. `run_save.gd`, run_state etc. → `autoload/`.

## `scenes/` layout (current)
Mirrors the above where applicable: `enemies/bosses/`, `enemies/core/`, `enemies/factions/
<faction>/`, plus flat `enemies/` (sub-units, mines, projectiles), `effects/`,
`projectiles/`, `parallax/`, `player/`, `hud/`, `dev/`. The top-level scene `.tscn` (main,
main_menu, outpost, …) stay at `scenes/` root; their scripts moved to `screens/`/`game/`.

## Where does my new file go?
| Adding… | Script → | Scene → |
|---|---|---|
| A menu / flow screen | `scripts/screens/` | `scenes/` root |
| A shared world/runtime system | `scripts/systems/` | — |
| An FX (particles/trail/shader/sfx) | `scripts/effects/` | `scenes/effects/` |
| An enemy (chaff/elite) | `scripts/enemies/{core,factions/<f>}/` | `scenes/enemies/{core,factions/<f>}/` |
| A boss | `scripts/enemies/bosses/` | `scenes/enemies/bosses/` |
| A movement/shoot pattern | `scripts/enemies/{patterns,shoot_patterns}/` | — (Resource) |
| A Part (upgrade/weapon) | `scripts/parts/` (+ register in PartCatalog) | `.tres` in `resources/weapons/` |
| A HUD widget | `scripts/hud/` | `scenes/hud/` |
| A dev tuner/lab | `scripts/dev/` | `scenes/dev/` |
| A string/codex table | `scripts/strings/` | — |

## Move-safety conventions (READ before relocating a file)
Godot tracks resources by BOTH `uid://` and literal `res://` path. The discipline this
reorg uses (change-map → move → verify → commit, one batch per commit):
1. **Map first.** `grep` every `res://oldpath` across `*.gd/*.tscn/*.tres/project.godot`.
   Watch for the silent-fail class: runtime `resource_path == "res://..."` compares + dict
   keys keyed by a path (e.g. `enemy_strings`, `wave_generator` boss roster) — these never
   fail at parse, only at runtime.
2. **Move + sidecar.** `git mv` the file AND its `.gd.uid`/`.png.import`. `git mv` does NOT
   create the destination dir — `mkdir -p` it first.
3. **Replace every literal** `res://oldpath` → `res://newpath` across all text files.
   `godot --import` re-resolves `uid://`, but NOT literal paths (`preload`/`load`/`extends`),
   path-only `ext_resource` (no `uid=`), or the 4 autoload paths.
4. **Verify:** `--import` → `tools/parse_check.ps1` + `compile_check` + a headless boot
   (and a domain boot, e.g. a boss spawn, for runtime-only refs).
5. **One batch = one commit** so any batch can be reverted cleanly.

## Reorg status
**DONE (2026-06-14) — the `scripts/` root is fully cleared.** All in their own verified
commits (compile 314/0 + boot each): `autoload/`, `effects/` (strays), `strings/`, `hud/`
(+ `ui.gd`), `enemies/bosses/` (scripts + scenes), `game/` (main/player/ship/run_save) +
`enemy_core` → `enemies/`, `screens/` + dev-screens → `dev/`, `systems/` + `galaxy_backdrop`
→ `parallax/` + `volume_slider` → `ui/`, and `Sound/` → `assets/audio/`.

**Remaining (deferred — highest surface / lowest value):**
- Graphics consolidation: `graphics/` → `assets/graphics/` (+ reshuffle the root PNGs into
  subdirs). Thousands of `res://graphics/...` literals — do as one mechanical prefix-replace
  (`res://graphics/` → `res://assets/graphics/`) + the "zero remaining" completeness check.
- `Mini Pixel Pack 3/` → `vendor/` (mostly vendor art; just the `project.godot` icon path +
  a few refs — note the **spaces** in the path).
- Orphan cleanup tracked separately in `docs/archive/file_reorg_audit_2026-06-14.md` (deferred).
