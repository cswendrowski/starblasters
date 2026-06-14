# File structure guide

How this project's files are organized + where new ones go. Companion to the architecture
tour in `docs/contributing/02-architecture.md` (that's *what the systems are*; this is
*where the files live*). Began 2026-06-14 as a staged reorg (change map:
`docs/file_reorg_changemap_2026-06-14.md`).

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
- `effects/` — ALL visual/audio FX (explosions, trails, muzzle, shaders, sfx wrappers,
  burn/shadow/trail_fx). Static-helper classes called as `Cls.method(...)`.
- `enemies/` — `enemy_base.gd` + `enemy_core.gd`'s peers; subdirs:
  `bosses/` (boss.gd + boss_*.gd + boss_base/phase), `core/` (universal chaff/elite),
  `factions/<faction>/` (faction-exclusive), `patterns/` (movement Resources),
  `shoot_patterns/` (weapon Resources), `components/` (EnemyComponent).
- `hud/` — in-combat HUD widgets: hud_light, hull_pips, shield_pips_hud, hologram_hud,
  score_counter, wave_banner. (`ui.gd`, the combat-UI root, currently still at root.)
- `strings/` — string/codex tables: strings, armory_strings, codex_strings, enemy_strings,
  sector_name_generator.
- `parts/` — Parts (slotted upgrades + weapons): Part subclasses + PartFactory/PartCatalog.
- `weapons/` — weapon plumbing: loadout, SlotTypes, WeaponStyle, enemy_bullet/rocket.
- `projectiles/` — base_bullet/base_missile + concrete projectile scripts.
- `levels/` — wave_generator, levels_v2, factions (the producer).
- `parallax/` — backdrop layers.
- `ui/` — shared UI framework: HdScreen, ui_theme, options_overlay.
- `dev/` — dev tools/tuners (enemy_bench, combat_lab, smart_mount_lab, parallax_tuner, …).
- `player/` — player helper scripts.

## `scenes/` layout (current)
Mirrors the above where applicable: `enemies/bosses/`, `enemies/core/`, `enemies/factions/
<faction>/`, plus flat `enemies/` (sub-units, mines, projectiles), `effects/`,
`projectiles/`, `parallax/`, `player/`, `hud/`, `dev/`. Top-level scene scripts (main,
main_menu, outpost, …) currently sit at `scripts/` root (see "Planned" below).

## Where does my new file go?
| Adding… | Script → | Scene → |
|---|---|---|
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
**Done (2026-06-14):** `autoload/`, `effects/` (strays folded in), `strings/`, `hud/`,
`enemies/bosses/` (scripts + scenes). ~30 files.

**Planned next phases** (mapped, not yet executed — higher blast / more subjective):
- `scripts/game/` ← main, player, ship, enemy_core, run_save
- `scripts/screens/` ← main_menu, outpost, manage_ship, signal_event, cleared_summary,
  run_summary, run_history, sector_map_v3, sector_map_hd, hangar, feature_showcase, credits,
  dev_menu, debug_testbed, pause_menu
- `scripts/systems/` ← playfield, lanes, lane_traffic, zones, clarity, scene_transition(_overlay),
  sector_node, sector_map_route, galaxy_backdrop, black_hole, beat, Camera2D, enemy_codex, ui
- assets: `Sound/` → `assets/audio/` (literal `res://Sound/...` in sfx/music scripts —
  string-replace), graphics consolidation, `Mini Pixel Pack 3/` → `vendor/`.
- Orphan cleanup is tracked separately in `docs/file_reorg_audit_2026-06-14.md` (deferred).
