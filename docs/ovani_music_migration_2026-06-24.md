# Ovani music migration — analysis & plan (2026-06-24)

Replacing the hand-rolled `Music` autoload (`scripts/autoload/music_manager.gd`)
with the **GodotMusicPlayer (Ovani)** addon (`addons/GodotMusicPlayer0.0.9/`).

Status: **MIGRATED (2026-06-24).** POC approved ("works fantastically out of the
box") → the live `Music` autoload now runs on Ovani, the 8 old loose 3-track sets
are retired, 16 new Ovani sets are wired, and a new dynamic intensity schema is
live. The Music Lab is now a full **Track Manager**. See "Built" below.

## How the Ovani addon works

Four scripts:

- **`OvaniSong`** (Resource) — one track's variants: `Intensity1/2/3`, optional
  `Loop30`/`Loop60`, a `ReverbTail` float, and a `SongMode`
  (`Intensities` / `Loop30` / `Loop60`).
- **`OvaniPlayer`** (Node) — the engine. `QueuedSongs: Array[OvaniSong]`,
  `Volume` (dB), continuous **`Intensity` 0.0–1.0**, `Bus`, `LoopQueue`.
  Methods: `PlaySongNow(song, transitionTime)`, `QueueSong`, `StopSongsNow`,
  `FadeIntensity(v, t)`, `FadeVolume(v, t)`; readouts `CurrentSongTime`,
  `CurrentSongLength`.
- **`SeamlessStream` / `SeamlessStreamManager`** — an alternative drop-in
  `AudioStream` that loops a single file via its reverb tail. Not needed here;
  `OvaniPlayer` is the real engine.

The core idea (`OvaniPlayer.gd:93-141`, `197-256`): it plays **all three
intensity stems simultaneously, phase-locked**, through one
`AudioStreamPolyphonic`. The `Intensity` knob runs a triangular crossfade across
the three synced stems in real time (`PolySoundManager.Volume` setter,
`OvaniPlayer.gd:105-109`). Because the stems are always at the same playback
position, intensity ramps mid-track with **zero phase glitch**. Looping is
**sample-accurate via the reverb tail**: within `ReverbTail` seconds of the end
it spawns an overlapping copy so the tail bleeds into the loop point
(`OvaniPlayer.gd:226-254`).

## Current system & the key difference

`music_manager.gd` does the same job by hand: 8 "sets" × 3 separate `.ogg`
files, two `AudioStreamPlayer`s swapping roles to crossfade, **discrete**
intensity 0/1/2 reached only at track boundaries (or a prompt tween), plus a
per-frame end-of-track lookahead **and** a `finished` safety net to fake looping
(the historical "music does not loop" bug source).

**The difference that matters:** our tiers are crossfaded as *independent files
at different playback positions*; Ovani crossfades *synced stems of one
composition*.

## Why migration is easy

**Our existing music is already in Ovani format.** Probed durations: Galaxy's
three tiers are all exactly `98.912042s`; Battle Tech's three are all `98.4s` —
phase-aligned synced stems. The `.ogg` imports are already `loop=false`, exactly
what Ovani needs (it manages looping itself). The test folders even encode the
reverb tail in their name: **"Battle Tech (RT 2.1)" → ReverbTail 2.1**,
**"Out The Way (RT 4.955)" → 4.955**. So existing sets migrate by re-wiring, not
re-authoring.

## Migration mapping (preserve the public API)

All 32 call sites use `get_node("/root/Music").<method>` — keep the autoload's
public surface identical and swap only its internals.

| Current API / concept | Ovani equivalent |
|---|---|
| A "set" = 3 loose preloads | One `OvaniSong` (`.tres`) |
| discrete idx 0 / 1 / 2 | continuous Intensity `0.0 / 0.5 / 1.0` |
| `_crossfade_to(set, idx)` + 2-player swap | `player.FadeIntensity(v, t)` (same song, no swap) |
| context change (switch set) | `player.PlaySongNow(song, t)` |
| per-frame lookahead + `finished` safety net | **deleted** — reverb-tail seamless loop |
| `set_combat_progress` step ramp | `FadeIntensity` — can ramp *smoothly* across waves |
| `stop(fade)` | `StopSongsNow` / `FadeVolume(-80, t)` |
| `set_walk_frozen` | keep flag; just gate the auto intensity-walk |
| `ramp_down` | `FadeIntensity(0.0, t)` |
| `notify_boss_spawned` | `FadeIntensity(1.0, t)` (currently dead — boss uses `set_context("boss")`) |
| `set_intensity(idx, fade)` (patrol hangar) | `FadeIntensity(idx/2.0, fade)` |

### Public API consumed (do not break)
- `set_context(context, options)` — menu/sector/signal/outpost/combat/boss/silent
- `set_combat_progress(wave_idx, total_waves, has_boss)` — `main.gd:345`
- `set_walk_frozen(bool)` — `pause_menu.gd`, `cleared_summary.gd`
- `ramp_down()` — `main.gd:430`, `cleared_summary.gd`
- `set_intensity(idx, fade)` — `patrol_start.gd:1152`
- `stop(fade)` — `main.gd:505`
- `notify_boss_spawned()` — defined, **no production caller** (boss_base uses `set_context("boss")`)

## Wins
- Kills the looping bug-class outright (no lookahead / `finished` net).
- Smoother, phase-locked intensity ramps — a real upgrade to combat escalation
  feel; `set_combat_progress` can ramp *continuously* across waves instead of
  stepping 0→1→2.
- One resource per song vs 3 loose preloads. Manager shrinks substantially.

## Risks / decisions
1. **Reverb tails for the 8 existing sets** — encoded in the source pack folder
   names (per Roman). Re-fetch the original Ovani pack folders, or re-organize
   our flat `X_Intensity_*` files into `Name (RT n.nn)/` folders, to recover
   them. Battle Tech (2.1) / Out The Way (4.955) are known.
2. **Pause-through** — `OvaniPlayer` advances on `_process` delta, so it must be
   `PROCESS_MODE_ALWAYS` to keep playing under the pause menu (the POC sets
   this).
3. **Addon hygiene** — fixed the broken `@icon` paths (pointed at a non-existent
   `res://OvaniPlugin/`; now `res://addons/GodotMusicPlayer0.0.9/`). No
   `plugin.cfg`, but the `class_name`s register globally so it isn't required.
4. **Intensity granularity** — old system is discrete 0/1/2; Ovani is continuous.
   Map 0→0.0, 1→0.5, 2→1.0 for parity, or embrace continuous ramps.
5. **Random-walk contexts** (menu/sector/etc.) — the old "1-2-Main-2-1 feel" can
   be a light `FadeIntensity`-to-random-target timer, or a fixed pleasant
   per-context intensity. Design choice.

## Built (2026-06-24)

### Data layer (catalog + eligibility)
- `scripts/systems/music_library_data.gd` — `MusicLibraryData` Resource: baked
  `tracks` (name → {rt, i1, i2, main, l30, l60 paths}) + `eligibility`
  (context → track names). Stored as `res://resources/music/music_library.tres`
  (a `.tres` is reliably bundled into exports; a loose `.json` is not).
- `scripts/systems/music_library.gd` — `MusicLibrary` helper: builds cached
  `OvaniSong`s from the catalog, answers `eligible(context)`, and owns the
  dev-only folder scanner (`scan_project_folders()` — parses `Name (RT n.nn)`,
  suffix-matches the 5 stems regardless of the varying `Ambient/Industrial/…`
  prefix).
- `tools/build_music_library.gd` — one-shot generator (scan + seed default
  eligibility → save the `.tres`). Re-run-safe (preserves edits). Run:
  `godot --headless --path . --script tools/build_music_library.gd`.

### Track Manager (`scripts/dev/music_lab.gd`)
Dev Menu → Music Lab. Browse all 16 tracks, select + listen, pan Intensity 0..1,
adjust volume, watch the loop point, and tick per-context eligibility checkboxes
(Main Menu / Sector / Events / Outpost / Combat / Boss). Save writes the catalog
`.tres`; Copy GDScript exports the eligibility dict; Rescan re-reads folders.

### Music autoload (`scripts/autoload/music_manager.gd`)
Rewritten over one `OvaniPlayer`. Public API preserved (`set_context`,
`set_combat_progress`, `ramp_down`, `set_intensity`, `set_walk_frozen`, `stop`,
`notify_boss_spawned`) **plus `notify_damage(max_hull, hull)` and
`notify_kill()`**. The
two-player swap, discrete tiers, per-frame lookahead, `finished` safety net, and
per-boss intensity floor are all gone.

**Dynamic combat intensity** — a CEILING the music ramps *up to*, never snaps to
(updated 2026-06-25 to a live per-frame envelope so combat opens quiet and breathes):

`ceiling = _combat_ceiling() = clamp(COMBAT_BASE 0.12 + W_WAVE 0.50·wave01 + W_PROGRESS 0.22·runDepth01 + W_DAMAGE 0.30·damage01, 0, 1)`
- `wave01` = wave_idx / (total-1) — deeper into the level = hotter.
- `runDepth01` = (sectors_cleared·4 + combats_in_sector) / 6 — deeper run = hotter open.
- `damage01` = 1 − hull/max_hull — fed by `notify_damage` off `hull_changed`.

Live intensity each frame (`_process`, combat only):
`intensity = clamp(presence · ceiling + W_STREAK 0.15 · streak_heat, 0, 1)`
- **presence** (0..1): `move_toward` the live enemy count / `CROWD_FULL 5`, rising at
  `PRESENCE_RISE 1.5`/s, falling at `PRESENCE_FALL 0.4`/s. Combat opens at presence 0
  (intensity 0) and ramps to the ceiling as enemies stream in; brief between-wave lulls
  dip gently (slow fall) instead of cutting out. Enemy count via the `"enemies"` group.
- **streak_heat** (0..1, mild): each kill adds `STREAK_GAIN 0.34` (capped), decays at
  `STREAK_DECAY 0.5`/s — a gentle lift while scoring fast, fading when the streak ends.
  Fed by `notify_kill()` off the director's `enemy_died` (main.gd `_on_enemy_died`).
`set_context("combat")` opens quiet (resets presence/streak/wave/damage, Intensity→0);
`ramp_down()` stops the envelope so the level-clear breather can settle.
Non-combat contexts rest at fixed levels (`CTX_INTENSITY`: menu/outpost 0.0,
sector 0.12, events 0.40, boss 1.0). Transitions use `PlaySongNow(song, fade)`;
intensity changes use `FadeIntensity`. Tuning lives in the constants block.

### Wiring + retirement
- `main.gd` forwards `player.hull_changed` → `Music.notify_damage` in combat setup.
- Imported all 16 Ovani folders (`loop=false`); **deleted the 24 old loose
  `X_Intensity_*` files**.
- `tools/test_music_ramp.gd` retargeted to the continuous schema — **PASS**
  (0.12 open → 0.62 deep-wave → 0.92 hurt; deep-run opens 0.34; ramp_down 0;
  boss 1.0).

### Verified
Parse-clean (335 scripts). Headless boots clean: Music Lab, main_menu,
sector_map_hd, outpost. Combat smoke + in-game audition (the seamless loop and
the intensity *feel*) are the remaining human-ear checks.

## Open follow-ups
- Tune the intensity weights + per-context resting levels to taste (constants in
  `music_manager.gd`; the curve is validated, the *feel* is Roman's call).
- Tune eligibility assignments in the Track Manager (defaults are vibe-guesses).
- Optional: a Music bus / Settings volume hookup if not already covered.
