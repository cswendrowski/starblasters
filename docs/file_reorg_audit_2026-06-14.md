# File-structure reorg — audit & plan (2026-06-14)

Status: **AUDIT ONLY — not executed.** Roman wants to review the orphan list + target
tree and run the reorg later on his own schedule (deferred while playtesting). This doc is
the reference for when that happens. Nothing here has been moved or deleted (one exception:
the corrupted `scripts/effects/enemy_smoke_trail.gd.uid` merge-conflict markers were fixed —
a standalone bug, committed with the particle round-up).

Verified against path + `uid://` references across ~872 source files (`.gd/.tscn/.tres/.godot`).

---

## 1. Current structure + inconsistencies

Top-level (recursive counts, excl. `.git`): `scripts/` 634 · `tools/` 494 · `Sound/` 446 (all
audio) · `graphics/` 438 (sprites + shaders) · `scenes/` 189 · `addons/` 119 · `Planets/` 73 ·
`docs/` 62 · `resources/` 51 · `SpaceBG/` 23 · `Mini Pixel Pack 3/` 90 · `data/` 16 · `shaders/` 2.

`scripts/` subdirs: `effects/` 48, `enemies/` 81 (`components/` 3, `core/` 4, `patterns/` 25,
`shoot_patterns/` 7, `factions/*`), `parts/` 60, `dev/` 22, `levels/` 12, `projectiles/` 11,
`parallax/` 9, `weapons/` 7, `ui/` 6, `player/` 2 — **plus 56 `.gd` at `scripts/` root.**

`scenes/` subdirs: `enemies/` 68, `projectiles/` 29, `dev/` 22, `effects/` 10, `parallax/` 8,
`player/` 6 — **plus 21 `.tscn` at `scenes/` root.**

**Inconsistencies:**
1. **Effects scripts split** — `scripts/effects/` (44) but `burn_fx.gd`, `shadow_fx.gd`,
   `trail_fx.gd` sit at `scripts/` root (CLAUDE.md already flags this).
2. **Boss scripts split** — `scripts/boss.gd` (Commander) at root; the other 8 (`boss_aegis/
   base/conductor/howler/phase/reaver/spinwright/voidmaw`) in `scripts/enemies/`. Boss `.tscn`
   are flat in `scenes/enemies/`, not under a `bosses/` subdir.
3. **Capitalized / spaced one-off top dirs** — `Sound/`, `Planets/`, `SpaceBG/`,
   `Mini Pixel Pack 3/`. `Planets/` near-duplicates `addons/PixelPlanetsSource/.../Planets/`.
4. **`scripts/` root is a catch-all** — autoloads (`run_state`, `dbg`, `music_manager`,
   `settings`), core game (`main`, `player`, `ship`, `enemy_core`), HUD (`hud_light`,
   `hull_pips`, `shield_pips_hud`), string tables (`strings`, `armory_strings`,
   `codex_strings`, `enemy_strings`), + the stray fx/boss files above.
5. **scripts↔scenes mirror is partial** — some projectile scripts live *inside*
   `scenes/projectiles/` (e.g. `bullet_autocannon.gd`, `bullet_minigun.gd`).
6. **`scripts/weapons/` mixes concerns** — live `loadout.gd`, dead `player_loadout.gd`,
   `enemy_bullet.gd`, `enemy_rocket.gd`, `shell_eject_small.gd`, `SlotTypes.gd`/`WeaponStyle.gd`.
7. **Texture dupes** — mine sprites in both `graphics/` root and `graphics/mines/`;
   `bar_foreground_white.png` in `graphics/ui/` and `Mini Pixel Pack 3/`.

---

## 2. Orphan / unused audit — KEEP-or-CUT decisions for Roman

Methodology: checked each candidate's filename AND its `uid://` against the whole corpus.
A file referenced only by uid still counts as USED. Autoloads, the main scene, and
dev_menu-launched scenes are entry points. **Conservative — flagged, not concluded.**

### High-confidence orphans (no path ref, no uid ref, no class_name use)

**Scripts:**
- `scripts/weapons/player_loadout.gd` — dead dup; live one is `weapons/loadout.gd`.
- `scripts/parallax/galaxy_backdrop_v2.gd` (12.5 KB) — superseded by v3/`galaxy_backdrop.gd`.
- `scripts/effects/glow_fx.gd` (3 KB) — only a string-name collision in `shader_lab.gd`.
- `scripts/effects/enemy_smoke_trail.gd` (`class_name EnemySmokeTrail`, used nowhere).
- `scripts/enemies/patterns/jet_vector.gd`, `…/inertial_thrust.gd` — no refs.
- (`scripts/dev/grid_overlay.gd` — no ref, but a dev utility → lower confidence.)

**Scenes:**
- `scenes/levels/level_1_1.tscn` (**144.5 KB**, largest) — replaced by `levels_v2.build_level_1_1()`.
- `level1-island-stretch.tscn` (root, 18.6 KB) — old prototype.
- `scenes/player/player_old.tscn` (9.6 KB) — only in dev `player_fx_lab.gd` ship list (`_b`/`_c` ARE live).
- `scenes/projectiles/{drifting_missile_large, enemy_rocket_large, player_rocket_large}.tscn`.
- `scenes/dev/{hud_live_capture, star_system_capture, light_patterns_test_simple}.tscn` — not dev-menu-launched.
- `tools/test_combat_play.tscn`, `SpaceBG/BackgroundGenerator.tscn`.

**Textures (~87, ~578 KB):**
- The whole **`Mini Pixel Pack 3/`** raw vendor pack (~42 PNGs).
- All 20 `graphics/extra-ships/tiny_ship*.png` (bosses use the sibling `ship_N.png`).
- `graphics/stars/Space_Stars1..9.png`, the whole `graphics/mines/` dir (dup of root `enemy-mine*.png`),
  many `graphics/enemies/small_*.png` + `enemy_placeholder_*.png`.

**Audio (3):** `Sound/weapons/player/Machinegun-End.ogg`, `Machinegun-Loop.ogg` (the `-LP`
variants are used), `rotary_laser_loop.ogg`.

### Likely-orphan but UNCERTAIN (verify before cutting)
- **17 `resources/patterns/*.tres`** (`enemy_blaster*`, `enemy_cannon`, `aimed_lead`,
  `burst_shot_3/5`, `spread_shot_7`, `weapon_mg*`, `movement/loiter`, …) — loaded dynamically
  by name only in `tools/test_weapon_intake.gd`. Production scenes use just `single_shot`,
  `aimed_wild`, `spread_shot_3`, `pair_shot`. **Keep unless you also retire that test.**
- `resources/weapons/{hyper_mode, phase_shift, side_pods}.tres` — names appear as Part IDs but
  the `.tres` aren't loaded by path/uid; confirm the intended wiring before removing.
- `shaders/outline_1px.gdshader` — no live ref surfaced, but shaders are often set in-editor.

### Scratch / build clutter (NOT in git — local-only)
`Classic Shmup.pck`, `Classic Shmup.console.exe`, `Starblasters.pck`, `shmup-v001.zip`,
`sim_out.txt`, `sim_stream_out.txt`, `ground_tilemap.aseprite`. Safe to delete from disk anytime.

---

## 3. Proposed target structure

```
scripts/
  autoload/   run_state, dbg, music_manager, settings        (HIGH risk)
  game/       main, ship, player, enemy_core                 (HIGH)
  effects/    + burn_fx, shadow_fx, trail_fx (from root)      (HIGH)
  enemies/
    bosses/   boss.gd + boss_* (consolidate the split)        (HIGH)
    …existing core/factions/patterns/components/shoot_patterns
  hud/        hud_light, hull_pips, shield_pips_hud, …         (MEDIUM)
  strings/    strings, armory_strings, codex_strings, …        (MEDIUM)
  weapons/, parts/, projectiles/, levels/, parallax/, ui/, dev/ (unchanged)
scenes/       mirror: bosses/ subdir; projectile scripts -> scripts/projectiles/
assets/
  graphics/   (absorb root PNGs into subdirs; drop graphics/mines dup)
  audio/      (Sound/ -> assets/audio/)
  backgrounds/ (fold SpaceBG/ + Planets/, or delete if dup of addon)
resources/, data/, shaders/   (unchanged)
vendor/       Mini Pixel Pack 3/   (raw packs out of project root)
```

### Risk-labeled batches (do in order; `tools/parse_check.ps1` + a boot after each)

- **Batch 0 — delete approved orphans (LOW, reversible via git).** The §2 high-confidence list.
  Decide separately on the 17 dev-only pattern `.tres`.
- **Batch 1 — leaf assets, uid-resolved (LOW, audio MEDIUM).** `Sound/` -> `assets/audio/`,
  consolidate `graphics/` root PNGs, `Mini Pixel Pack 3/` -> `vendor/`. **Caveat:** audio is
  referenced by literal `res://Sound/...` strings in `enemy_sfx.gd`, `explosion_sfx.gd`,
  `weapon_sfx.gd`, `music_manager.gd` — those must be string-replaced (→ MEDIUM).
- **Batch 2 — standalone `.tres` (LOW–MEDIUM).** Most uid-referenced (LOW); `data/bullets/*`
  are loaded by hardcoded `res://data/bullets/...` strings in boss scripts (MEDIUM).
- **Batch 3 — scenes referenced by a few others (MEDIUM).** `scenes/enemies/boss_*.tscn` ->
  `bosses/`; a handful of path edits in `enemy_roster.gd`/`factions.gd`/boss pairing per file.
- **Batch 4 — scripts: many tscn / autoloads / class_name (HIGH).** Move `scripts/` root files
  into `autoload/`, `game/`, `hud/`, `strings/`; consolidate fx/boss splits. One logical group
  per commit, parse_check + boot after each.

### The load-bearing gotcha
The project uses **both** `uid://` and literal `res://` path references. `godot --import`
re-resolves `uid://` after a move, but **NOT** literal path strings inside `.gd`
(`preload`/`load`/`extends "res://..."`) or the 4 autoload paths in `project.godot`. After
every move: grep the literal path. Highest-risk literals: shoot_pattern subclasses
`extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"`, the sfx/music `res://Sound/...`
preloads, and `data/bullets/*` loads. See the memory note "Moving UID-referenced scripts".
