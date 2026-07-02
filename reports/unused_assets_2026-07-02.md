# Unused sprites & audio audit

_Generated 2026-07-02 by reference-graph reachability from `project.godot` roots
(main scene, autoloads, theme, icon, editor plugins). A file is "unused" if no reachable
`.gd`/`.tscn`/`.tres` references it by `res://` path, UID, or `class_name`. Sizes include the
`.import` sidecar. Verified by hand against the music library, backdrop, and dev menu._

**Totals: 133 unused sprites + 3 unused audio = 1201 KB**

---
# AUDIO
## Unused audio  (3 files, 106 KB)

**`assets/audio/weapons/player/`** — 3 files, 105.8 KB

- `Machinegun-Loop.ogg` — 49.6 KB
- `Machinegun-End.ogg` — 44.7 KB
- `rotary_laser_loop.ogg` — 11.5 KB

---
# SPRITES
## Project art — safe to cut  (49 files, 825 KB)

> Your own art, unreferenced anywhere. `graphics/tilesets/` + `ground_tilemap.aseprite` are tilemap art (no tilemaps in this game); `graphics/extra-ships/` is an unused ship pack; `icon.svg` is superseded by the PNG icon in project.godot.

**`(repo root)/`** — 2 files, 49.1 KB

- `ground_tilemap.aseprite` — 44.0 KB
- `icon.svg` — 5.1 KB

**`graphics/`** — 5 files, 5.4 KB

- `enemy-mine-shield.png` — 1.3 KB
- `enemy-mine-cluster.png` — 1.3 KB
- `enemy-mine-cluster-small.png` — 1.3 KB
- `enemy-mine-bomblet.png` — 1.1 KB
- `tracer-yellow.aseprite` — 0.4 KB

**`graphics/backgrounds/`** — 1 files, 2.7 KB

- `outpost_clutter_crates.png` — 2.7 KB

**`graphics/effects/`** — 1 files, 3.2 KB

- `smoke_pulse.png` — 3.2 KB

**`graphics/extra-ships/`** — 19 files, 304.8 KB

- `tiny_ship9.png` — 19.6 KB
- `tiny_ship14.png` — 19.5 KB
- `tiny_ship7.png` — 19.5 KB
- `tiny_ship5.png` — 19.5 KB
- `tiny_ship2.png` — 19.4 KB
- `tiny_ship10.png` — 19.4 KB
- `tiny_ship13.png` — 19.4 KB
- `tiny_ship6.png` — 19.3 KB
- `tiny_ship8.png` — 19.3 KB
- `tiny_ship12.png` — 19.3 KB
- `tiny_ship15.png` — 19.2 KB
- `tiny_ship3.png` — 19.1 KB
- `tiny_ship4.png` — 19.1 KB
- `tiny_ship1.png` — 19.0 KB
- `tiny_ship19.png` — 7.4 KB
- `tiny_ship20.png` — 7.2 KB
- `tiny_ship18.png` — 6.9 KB
- `tiny_ship17.png` — 6.4 KB
- `tiny_ship16.png` — 6.4 KB

**`graphics/projectiles/`** — 6 files, 6.5 KB

- `projectile_tracer.png` — 1.1 KB
- `missile-orange.png` — 1.1 KB
- `missile-finned.png` — 1.1 KB
- `missile-teal.png` — 1.1 KB
- `tracer-large-yellow.png` — 1.1 KB
- `tracer-yellow.png` — 1.0 KB

**`graphics/sector/`** — 1 files, 42.7 KB

- `sector-start.png` — 42.7 KB

**`graphics/stars/`** — 9 files, 21.7 KB

- `Space_Stars3.png` — 3.8 KB
- `Space_Stars5.png` — 2.8 KB
- `Space_Stars7.png` — 2.7 KB
- `Space_Stars1.png` — 2.6 KB
- `Space_Stars8.png` — 2.5 KB
- `Space_Stars4.png` — 2.3 KB
- `Space_Stars9.png` — 1.9 KB
- `Space_Stars6.png` — 1.9 KB
- `Space_Stars2.png` — 1.4 KB

**`graphics/tilesets/`** — 2 files, 384.5 KB

- `ground_tilemap.png` — 192.5 KB
- `ground_tilemap_templated.png` — 192.0 KB

**`graphics/ui/`** — 3 files, 4.1 KB

- `shield_pips.png` — 1.5 KB
- `bar_background.png` — 1.5 KB
- `bar_foreground_white.png` — 1.1 KB

## Staged enemy/mine art — CONFIRM before cutting  (41 files, 61 KB)

> Unreferenced, but these look like placeholder/staged sprites for enemies not yet wired (per the gap-unit sprite backlog). Check against TODO.md first — may be intentional staging.

**`graphics/enemies/`** — 33 files, 50.6 KB

- `enemy_placeholder_128x.png` — 2.7 KB
- `enemy_gunship.png` — 2.0 KB
- `firecore_cruiser.png` — 1.9 KB
- `enemy_bomber.png` — 1.9 KB
- `enemy_inteceptor.png` — 1.8 KB
- `enemy_p_s_minelayer.png` — 1.7 KB
- `enemy_minelayer.png` — 1.7 KB
- `enemy-harpy-sheet.png` — 1.6 KB
- `small_hover.png` — 1.6 KB
- `small_firecore.png` — 1.6 KB
- `drone_firecore.png` — 1.5 KB
- `enemy_c_s_drop.png` — 1.5 KB
- `small_cutter.png` — 1.5 KB
- `enemy-manta-sheet.png` — 1.5 KB
- `small_green.png` — 1.5 KB
- `enemy_p_s_drop.png` — 1.5 KB
- `enemy_c_s_gray.png` — 1.5 KB
- `enemy_p_s_green.png` — 1.4 KB
- `enemy_p_s_gray.png` — 1.4 KB
- `enemy_placeholder_32x.png` — 1.4 KB
- `small_drifter.png` — 1.4 KB
- `drone_bomblet_omni.png` — 1.4 KB
- `enemy_c_s_curve.png` — 1.4 KB
- `small_strafer.png` — 1.4 KB
- `enemy_c_s_hold.png` — 1.4 KB
- `enemy_p_s_jet.png` — 1.4 KB
- `small_orange.png` — 1.4 KB
- `small_skirmisher.png` — 1.3 KB
- `small_manta.png` — 1.3 KB
- `small_weaver.png` — 1.3 KB
- `impact_drone.png` — 1.3 KB
- `drone_bomblet_jet.png` — 1.3 KB
- `yellow-enemy-jet.png` — 1.3 KB

**`graphics/mines/`** — 8 files, 10.5 KB

- `mine_smart.png` — 1.6 KB
- `mine_shielded.png` — 1.5 KB
- `Enemy-Mine.png` — 1.4 KB
- `mine_mega_cluster.png` — 1.3 KB
- `mine_cluster.png` — 1.3 KB
- `mine_basic.png` — 1.2 KB
- `mine_smart_bomblet.png` — 1.2 KB
- `mine_bomblet.png` — 1.1 KB

## Vendor-pack leftovers — normal, leave unless reclaiming space  (43 files, 209 KB)

> Unused files inside imported third-party packs/addons. Deleting individual files here is low value and can break the pack on re-import.

**`Mini Pixel Pack 3/`** — 1 files, 1.6 KB

- `Space_BG (2 frames) (64 x 64).png` — 1.6 KB

**`Mini Pixel Pack 3/Effects/`** — 7 files, 32.4 KB

- `Ship_Exhaust.png` — 14.0 KB
- `Laser_01.png` — 10.6 KB
- `32x32 textures (19).png` — 2.0 KB
- `32x32 textures (52).png` — 1.8 KB
- `32x32 textures (50).png` — 1.4 KB
- `Sparkle (16 x 16).png` — 1.3 KB
- `32x32 textures (60).png` — 1.3 KB

**`Mini Pixel Pack 3/Enemies/`** — 4 files, 6.6 KB

- `mine.png` — 2.1 KB
- `Alan (16 x 16).png` — 1.6 KB
- `Lips (16 x 16).png` — 1.5 KB
- `Bon_Bon (16 x 16).png` — 1.4 KB

**`Mini Pixel Pack 3/Items/`** — 1 files, 1.4 KB

- `Power_item (16 x 16).png` — 1.4 KB

**`Mini Pixel Pack 3/Player ship/`** — 5 files, 7.1 KB

- `Player_ship_alt (16 x 16).png` — 1.7 KB
- `Player_ship (16 x 16).png` — 1.5 KB
- `Boosters_right (16 x 16).png` — 1.3 KB
- `Boosters_left (16 x 16).png` — 1.3 KB
- `Boosters (16 x 16).png` — 1.3 KB

**`Mini Pixel Pack 3/Projectiles/`** — 11 files, 16.5 KB

- `SpaceShooterAssetPack_Projectiles.png` — 2.9 KB
- `Player_charged_square_shot (16 x 16).png` — 1.9 KB
- `Player_missile_shots (16 x 16).png` — 1.6 KB
- `Enemy_projectile (16 x 16).png` — 1.4 KB
- `Player_charged_donut_shot (16 x 16).png` — 1.4 KB
- `Player_square_shot (16 x 16).png` — 1.4 KB
- `Player_charged_beam (16 x 16).png` — 1.3 KB
- `Player_beam (16 x 16).png` — 1.2 KB
- `Player_beam_single_alternating (16 x 16).png` — 1.2 KB
- `shot.png` — 1.1 KB
- `Player_beam_single (16 x 16).png` — 1.1 KB

**`Mini Pixel Pack 3/UI objects/`** — 2 files, 2.6 KB

- `Power_+_charge_bars (full + empty) (32 x 16).png` — 1.5 KB
- `bar_foreground_white.png` — 1.1 KB

**`SpaceBG/`** — 3 files, 11.2 KB

- `stars.png` — 7.8 KB
- `stars-special.png` — 1.9 KB
- `100x100.png` — 1.4 KB

**`addons/GodotMusicPlayer0.0.9/`** — 1 files, 116.7 KB

- `- Thank You.png` — 116.7 KB

**`addons/PixelPlanetsSource/PixelPlanets/`** — 2 files, 6.1 KB

- `icon.png` — 5.1 KB
- `stars.png` — 1.0 KB

**`addons/PixelPlanetsSource/PixelPlanets/GUI/`** — 6 files, 7.2 KB

- `check.png` — 1.3 KB
- `progress-over.png` — 1.3 KB
- `progress-under.png` — 1.3 KB
- `uncheck.png` — 1.3 KB
- `grabber-highlight.png` — 1.0 KB
- `grabber.png` — 0.9 KB
