# Orphaned files audit — scenes, scripts, shaders, resources, sprites, audio

_Regenerated **2026-07-17** (supersedes the 2026-07-02 run). Method: reference-graph reachability
from `project.godot` roots — main scene, the 5 autoloads, the GUI theme, the icon, enabled editor
plugins, plus Godot's implicit `default_bus_layout.tres`. A file counts as **used** if any reachable
`.gd`/`.tscn`/`.tres`/`.gdshader`/`.cfg` references it by `res://` path, UID, or `class_name`.
Comment mentions do **not** count as usage. Sizes include `.import`/`.uid` sidecars._

**318 orphaned files, 2126 KB** (excludes `tools/`, see Scope below).

> ⚠️ **Read the Caution list before deleting anything.** Some orphans are deliberately parked or
> are in-flight work from the last two weeks.

## Dead scripts (`.gd`) — 17 files, 200 KB

**`scenes/`** — 2 files, 0.3 KB

- `end_zone.gd` — 0.2 KB — reachable only from dead files (level_1_1.tscn)
- `parallax_background.gd` — 0.1 KB — reachable only from dead files (level_1_1.tscn)

**`scripts/effects/`** — 3 files, 3.9 KB

- `dust_fragment.gd` — 2.9 KB
- `particle_trail.gd` — 0.8 KB
- `enemy_smoke_trail.gd` — 0.2 KB

**`scripts/game/`** — 1 files, 1.5 KB

- `ship.gd` — 1.5 KB

**`scripts/hud/`** — 3 files, 5.8 KB

- `shield_pips_hud.gd` — 2.8 KB — reachable only from dead files (shield_pips_demo.gd)
- `hull_pips.gd` — 2.6 KB
- `score_counter.gd` — 0.4 KB — reachable only from dead files (score_counter.tscn)

**`scripts/parallax/`** — 3 files, 92.3 KB

- `galaxy_backdrop.gd` — 56.7 KB — reachable only from dead files (capture_engine_torch.gd, capture_horizontal_proof.gd)
- `galaxy_backdrop_v3.gd` — 23.1 KB — reachable only from dead files (capture_v3_standalone.gd)
- `galaxy_backdrop_v2.gd` — 12.5 KB

**`scripts/screens/`** — 1 files, 86.0 KB

- `outpost.gd` — 86.0 KB — reachable only from dead files (outpost.tscn, test_outpost_safeguard.gd)

**`scripts/systems/`** — 1 files, 0.7 KB

- `scene_transition_overlay.gd` — 0.7 KB — reachable only from dead files (scene_transition.tscn)

**`scripts/ui/`** — 1 files, 9.5 KB

- `ship_select_overlay.gd` — 9.5 KB — reachable only from dead files (test_ship_select_modal.gd)

**`scripts/weapons/`** — 2 files, 0.3 KB

- `player_loadout.gd` — 0.2 KB
- `shell_eject_small.gd` — 0.1 KB

## Dead scenes (`.tscn`) — 19 files, 190 KB

**`(repo root)/`** — 1 files, 18.6 KB

- `level1-island-stretch.tscn` — 18.6 KB

**`scenes/`** — 2 files, 2.7 KB

- `score_counter.tscn` — 2.4 KB
- `outpost.tscn` — 0.3 KB — reachable only from dead files (feature_showcase.gd, capture_all_screens.gd)

**`scenes/effects/`** — 10 files, 12.5 KB

- `smoke_trail.tscn` — 1.8 KB
- `muzzle_smoke.tscn` — 1.6 KB
- `fire_trail.tscn` — 1.6 KB
- `bullet_trail.tscn` — 1.4 KB
- `burning_trail2.tscn` — 1.3 KB
- `burning_trail.tscn` — 1.3 KB
- `engine_blast.tscn` — 1.3 KB
- `brass_wisp.tscn` — 1.1 KB
- `scene_transition.tscn` — 0.9 KB — reachable only from dead files (feature_showcase.gd)
- `asteroid_destroy.tscn` — 0.1 KB

**`scenes/levels/`** — 1 files, 144.5 KB

- `level_1_1.tscn` — 144.5 KB

**`scenes/outpost/`** — 3 files, 1.1 KB

- `outpost_ammo_crates.tscn` — 0.4 KB
- `outpost_6px_crates.tscn` — 0.4 KB
- `outpost_7px_crates.tscn` — 0.4 KB

**`scenes/player/`** — 1 files, 9.7 KB

- `player_old.tscn` — 9.7 KB

**`scenes/projectiles/`** — 1 files, 1.0 KB

- `player_rocket_large.tscn` — 1.0 KB

## Dead shaders (`.gdshader`) — 6 files, 10 KB

**`(repo root)/`** — 1 files, 1.2 KB

- `outline_glow.gdshader` — 1.2 KB

**`graphics/`** — 3 files, 8.3 KB

- `scene_transition.gdshader` — 3.7 KB — reachable only from dead files (scene_transition.tscn)
- `nebula.gdshader` — 2.5 KB — reachable only from dead files (galaxy_backdrop.gd, galaxy_backdrop_v2.gd)
- `screen_glow.gdshader` — 2.1 KB

**`scenes/`** — 2 files, 0.9 KB

- `player.gdshader` — 0.6 KB
- `player_shadow.gdshader` — 0.3 KB

## Dead resources (`.tres`) — 6 files, 2 KB

**`(repo root)/`** — 1 files, 0.3 KB

- `score_image.tres` — 0.3 KB

**`resources/patterns/movement/`** — 1 files, 0.2 KB

- `loiter.tres` — 0.2 KB

**`resources/patterns/shoot/`** — 1 files, 0.3 KB

- `pair_shot.tres` — 0.3 KB

**`resources/weapons/`** — 3 files, 1.0 KB

- `side_pods.tres` — 0.5 KB
- `hyper_mode.tres` — 0.3 KB
- `phase_shift.tres` — 0.3 KB

## Dev tools unwired from `dev_menu.gd` — 22 files, 128 KB

Present in the tree but no longer launchable — `dev_menu.gd` doesn't reference them; only
one-off `tools/capture_*.gd` scripts do.

**`scenes/dev/`** — 14 files, 12.5 KB

- `light_patterns_demo.gd` — 4.5 KB — reachable only from dead files (light_patterns_demo.tscn)
- `hud_mockup.gd` — 4.0 KB — reachable only from dead files (hud_mockup.tscn)
- `light_patterns_test_simple.gd` — 1.4 KB — reachable only from dead files (light_patterns_test_simple.tscn)
- `shield_pips_demo.tscn` — 0.3 KB — reachable only from dead files (capture_dev_screens.gd, capture_shield_gif.gd)
- `maneuver_sim.tscn` — 0.3 KB — reachable only from dead files (capture_dev_screens.gd)
- `movement_test.tscn` — 0.3 KB — reachable only from dead files (capture_dev_screens.gd)
- `draw_index_combat_repro.tscn` — 0.2 KB
- `light_patterns_test_simple.tscn` — 0.2 KB
- `draw_index_crash_lab.tscn` — 0.2 KB
- `feature_showcase.tscn` — 0.2 KB — reachable only from dead files (capture_dev_screens.gd)
- `light_patterns_demo.tscn` — 0.2 KB — reachable only from dead files (capture_light_patterns.gd)
- `star_system_capture.tscn` — 0.2 KB
- `hud_live_capture.tscn` — 0.2 KB
- `hud_mockup.tscn` — 0.2 KB — reachable only from dead files (capture_hud_mockup.gd)

**`scripts/dev/`** — 8 files, 115.0 KB

- `sector_map_v3.gd` — 39.3 KB
- `feature_showcase.gd` — 24.0 KB — reachable only from dead files (feature_showcase.tscn)
- `draw_index_combat_repro.gd` — 13.4 KB — reachable only from dead files (draw_index_combat_repro.tscn)
- `maneuver_sim.gd` — 12.5 KB — reachable only from dead files (maneuver_sim.tscn)
- `movement_test.gd` — 11.6 KB — reachable only from dead files (movement_test.tscn)
- `draw_index_crash_lab.gd` — 8.3 KB — reachable only from dead files (draw_index_crash_lab.tscn)
- `shield_pips_demo.gd` — 3.2 KB — reachable only from dead files (shield_pips_demo.tscn)
- `grid_overlay.gd` — 2.7 KB

## Unused sprites / images — 90 files, 863 KB

**`(repo root)/`** — 1 files, 5.1 KB

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

**`graphics/extra-ships/`** — 20 files, 324.3 KB

- `tiny_ship9.png` — 19.6 KB
- `tiny_ship11.png` — 19.5 KB
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

**`graphics/mines/`** — 8 files, 10.5 KB

- `mine_smart.png` — 1.6 KB
- `mine_shielded.png` — 1.5 KB
- `Enemy-Mine.png` — 1.4 KB
- `mine_mega_cluster.png` — 1.3 KB
- `mine_cluster.png` — 1.3 KB
- `mine_basic.png` — 1.2 KB — reachable only from dead files (galaxy_backdrop.gd)
- `mine_smart_bomblet.png` — 1.2 KB
- `mine_bomblet.png` — 1.1 KB

**`graphics/projectiles/`** — 6 files, 6.5 KB

- `projectile_tracer.png` — 1.1 KB
- `missile-orange.png` — 1.1 KB
- `missile-finned.png` — 1.1 KB
- `missile-teal.png` — 1.1 KB
- `tracer-large-yellow.png` — 1.1 KB
- `tracer-yellow.png` — 1.0 KB — reachable only from dead files (enemy_bomber_wing.gd)

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

- `ground_tilemap.png` — 192.5 KB — reachable only from dead files (level1-island-stretch.tscn, level_1_1.tscn)
- `ground_tilemap_templated.png` — 192.0 KB

**`graphics/ui/`** — 3 files, 5.8 KB

- `hud_annunciator_danger.png` — 2.9 KB — reachable only from dead files (hud_mockup.gd)
- `shield_pips.png` — 1.5 KB
- `hud_hull_light.png` — 1.4 KB — reachable only from dead files (hull_pips.gd)

## Unused audio — 3 files, 106 KB

**`assets/audio/weapons/player/`** — 3 files, 105.8 KB

- `Machinegun-Loop.ogg` — 49.6 KB
- `Machinegun-End.ogg` — 44.7 KB
- `rotary_laser_loop.ogg` — 11.5 KB

## Vendor-pack leftovers (leave unless reclaiming space) — 133 files, 560 KB

Unused files inside imported third-party packs/addons. Deleting individual files here is low
value and can break the pack on re-import.

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

**`Mini Pixel Pack 3/Items/`** — 2 files, 2.9 KB

- `Circle_+_Square_+_Missile_pick-ups (16 x 16).png` — 1.5 KB
- `Power_item (16 x 16).png` — 1.4 KB

**`Mini Pixel Pack 3/Player ship/`** — 5 files, 7.1 KB

- `Player_ship_alt (16 x 16).png` — 1.7 KB
- `Player_ship (16 x 16).png` — 1.5 KB — reachable only from dead files (hud_mockup.gd, player_old.tscn)
- `Boosters_right (16 x 16).png` — 1.3 KB — reachable only from dead files (player_old.tscn)
- `Boosters_left (16 x 16).png` — 1.3 KB — reachable only from dead files (player_old.tscn)
- `Boosters (16 x 16).png` — 1.3 KB — reachable only from dead files (player_old.tscn)

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

**`Mini Pixel Pack 3/UI objects/`** — 4 files, 5.2 KB

- `Power_+_charge_bars (full + empty) (32 x 16).png` — 1.5 KB
- `Number_font (8 x 8).png` — 1.3 KB — reachable only from dead files (score_counter.tscn, score_image.tres)
- `Item_held_box (16 x 16).png` — 1.3 KB
- `bar_foreground_white.png` — 1.1 KB

**`Planets/Asteroids/`** — 1 files, 1.5 KB

- `baked_atlas.gdshader` — 1.5 KB

**`SpaceBG/`** — 8 files, 27.0 KB

- `StarParticles.tres` — 8.5 KB
- `stars.png` — 7.8 KB
- `Nebulae.gdshader` — 3.2 KB
- `StarStuff.gdshader` — 2.9 KB
- `stars-special.png` — 1.9 KB
- `100x100.png` — 1.4 KB
- `Nebulae.tres` — 0.7 KB
- `StarStuff.tres` — 0.6 KB

**`addons/GodotMusicPlayer0.0.9/`** — 3 files, 118.5 KB

- `- Thank You.png` — 116.7 KB
- `SeamlessStreamManager.gd` — 1.2 KB — reachable only from dead files (SeamlessStream.gd)
- `SeamlessStream.gd` — 0.6 KB — reachable only from dead files (SeamlessStreamManager.gd)

**`addons/PixelPlanetsSource/PixelPlanets/`** — 4 files, 14.6 KB

- `slkscre.ttf` — 8.3 KB — reachable only from dead files (Theme.tres)
- `icon.png` — 5.1 KB
- `stars.png` — 1.0 KB — reachable only from dead files (GUI.tscn)
- `default_env.tres` — 0.2 KB

**`addons/PixelPlanetsSource/PixelPlanets/GUI/`** — 15 files, 118.0 KB

- `Theme.tres` — 66.4 KB — reachable only from dead files (GUI.tscn)
- `GUI.tscn` — 26.6 KB
- `GUI.gd` — 10.9 KB
- `SpritesheetPopup.gd` — 1.9 KB
- `GifPopup.gd` — 1.6 KB
- `check.png` — 1.3 KB — reachable only from dead files (Theme.tres)
- `progress-over.png` — 1.3 KB — reachable only from dead files (GUI.tscn)
- `progress-under.png` — 1.3 KB — reachable only from dead files (GUI.tscn)
- `uncheck.png` — 1.3 KB — reachable only from dead files (Theme.tres)
- `ColorPickerButton.tscn` — 1.2 KB — reachable only from dead files (GUI.tscn)
- `ImportExportPopup.gd` — 1.1 KB
- `grabber-highlight.png` — 1.0 KB — reachable only from dead files (Theme.tres)
- `grabber.png` — 0.9 KB — reachable only from dead files (Theme.tres)
- `ColorPickerButton.gd` — 0.8 KB
- `StarParticles.tres` — 0.5 KB — reachable only from dead files (GUI.tscn)

**`addons/PixelPlanetsSource/PixelPlanets/Planets/`** — 2 files, 2.4 KB

- `Planet.gd` — 2.1 KB
- `Planet.tscn` — 0.3 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/Asteroids/`** — 3 files, 5.4 KB

- `Asteroids.gdshader` — 3.1 KB
- `Asteroid.tscn` — 1.1 KB
- `Asteroid.gd` — 1.1 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/BlackHole/`** — 4 files, 9.3 KB

- `BlackHoleRing.gdshader` — 5.2 KB
- `BlackHole.tscn` — 1.9 KB
- `BlackHole.gd` — 1.6 KB
- `BlackHole.gdshader` — 0.6 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/DryTerran/`** — 2 files, 5.4 KB

- `DryTerran.tscn` — 4.2 KB
- `DryTerran.gd` — 1.2 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/Galaxy/`** — 3 files, 5.8 KB

- `Galaxy.gdshader` — 3.2 KB
- `Galaxy.tscn` — 1.4 KB
- `Galaxy.gd` — 1.2 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/GasPlanet/`** — 3 files, 7.2 KB

- `GasPlanet.gdshader` — 3.3 KB
- `GasPlanet.tscn` — 2.1 KB
- `GasPlanet.gd` — 1.9 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/GasPlanetLayers/`** — 4 files, 12.0 KB

- `GasLayers.gdshader` — 3.8 KB
- `Ring.gdshader` — 3.3 KB
- `GasPlanetLayers.tscn` — 2.7 KB
- `GasPlanetLayers.gd` — 2.2 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/IceWorld/`** — 2 files, 7.9 KB

- `IceWorld.tscn` — 5.2 KB
- `IceWorld.gd` — 2.7 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/LandMasses/`** — 5 files, 15.4 KB

- `PlanetLandmass.gdshader` — 3.4 KB
- `Clouds.gdshader` — 3.3 KB
- `PlanetUnder.gdshader` — 3.0 KB
- `LandMasses.tscn` — 3.0 KB
- `LandMasses.gd` — 2.8 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/LavaWorld/`** — 3 files, 7.8 KB

- `LavaWorld.tscn` — 2.7 KB
- `LavaWorld.gd` — 2.6 KB
- `Rivers.gdshader` — 2.4 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/NoAtmosphere/`** — 4 files, 8.5 KB

- `NoAtmosphere.gdshader` — 2.7 KB
- `Craters.gdshader` — 2.1 KB
- `NoAtmosphere.tscn` — 2.0 KB
- `NoAtmosphere.gd` — 1.8 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/Rivers/`** — 3 files, 8.2 KB

- `LandRivers.gdshader` — 3.8 KB
- `Rivers.gd` — 2.2 KB
- `Rivers.tscn` — 2.2 KB

**`addons/PixelPlanetsSource/PixelPlanets/Planets/Star/`** — 5 files, 15.0 KB

- `StarFlares.gdshader` — 3.6 KB
- `Star.gd` — 3.5 KB
- `Star.gdshader` — 2.9 KB
- `Star.tscn` — 2.7 KB
- `StarBlobs.gdshader` — 2.4 KB

**`addons/PixelPlanetsSource/PixelPlanets/addons/gdgifexporter/`** — 5 files, 11.5 KB

- `exporter.gd` — 8.5 KB
- `converter.gd` — 2.0 KB
- `lookup_similar.gdshader` — 0.5 KB
- `lookup_color.gdshader` — 0.4 KB
- `little_endian.gd` — 0.1 KB

**`addons/PixelPlanetsSource/PixelPlanets/addons/gdgifexporter/gif-lzw/`** — 3 files, 5.3 KB

- `lzw.gd` — 3.9 KB
- `lsbbitunpacker.gd` — 0.9 KB
- `lsbbitpacker.gd` — 0.6 KB

**`addons/PixelPlanetsSource/PixelPlanets/addons/gdgifexporter/quantization/`** — 2 files, 6.0 KB

- `median_cut.gd` — 3.8 KB
- `uniform.gd` — 2.1 KB

**`addons/godot_mcp/`** — 3 files, 15.2 KB

- `mcp_server.gd` — 7.9 KB
- `websocket_server.gd` — 4.7 KB — reachable only from dead files (mcp_panel.gd)
- `command_handler.gd` — 2.6 KB — reachable only from dead files (mcp_server.gd)

**`addons/godot_mcp/commands/`** — 7 files, 46.8 KB

- `script_commands.gd` — 10.0 KB — reachable only from dead files (command_handler.gd)
- `scene_commands.gd` — 8.7 KB — reachable only from dead files (command_handler.gd)
- `node_commands.gd` — 6.9 KB — reachable only from dead files (command_handler.gd)
- `project_commands.gd` — 6.7 KB — reachable only from dead files (command_handler.gd)
- `editor_commands.gd` — 5.1 KB — reachable only from dead files (command_handler.gd)
- `editor_script_commands.gd` — 5.0 KB — reachable only from dead files (command_handler.gd)
- `base_command_processor.gd` — 4.3 KB — reachable only from dead files (editor_commands.gd, editor_script_commands.gd)

**`addons/godot_mcp/ui/`** — 2 files, 5.6 KB

- `mcp_panel.gd` — 3.1 KB — reachable only from dead files (mcp_panel.tscn)
- `mcp_panel.tscn` — 2.5 KB

**`addons/godot_mcp/utils/`** — 3 files, 7.4 KB

- `script_utils.gd` — 3.1 KB
- `resource_utils.gd` — 2.4 KB
- `node_utils.gd` — 1.9 KB

## ⚠️ Caution — parked, cited, or in-flight (do NOT bulk-delete)

| File | Size | Why it's flagged |
|---|---|---|
| `scripts/dev/ui_designer.gd` | 23.4 KB | CLAUDE.md cites this as the canonical tuner-scaffolding template. |
| `scripts/enemies/enemy_bomber_wing.gd` | 10.7 KB | self-documented "PRESERVED" in its header |
| `graphics/enemies/ground/building_round_bunker_scatter.png` | 4.2 KB | **added 2026-07-12** — new but not yet wired up |
| `scripts/effects/engine_glow.gd` | 3.2 KB | self-documented "legacy" in its header; **added 2026-07-14** — new but not yet wired up |
| `graphics/proc_clouds.gdshader` | 2.9 KB | self-documented "PARKED" in its header; **added 2026-07-14** — new but not yet wired up |
| `graphics/enemies/enemy_s_m_missile.png` | 2.2 KB | **added 2026-07-06** — new but not yet wired up |
| `graphics/noise_puff.gdshader` | 2.0 KB | self-documented "preserved" in its header |
| `graphics/enemies/boss_c_director_bay_covers.png` | 1.7 KB | **added 2026-07-09** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_rush.png` | 1.6 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_bully.png` | 1.6 KB | **added 2026-07-17** — new but not yet wired up |
| `scenes/effects/explosion_small_fireball.tscn` | 1.6 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_hotrod.png` | 1.5 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_spearhead.png` | 1.4 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_striker.png` | 1.4 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/ground/enemy_s_s_piercer.png` | 1.4 KB | **added 2026-07-17** — new but not yet wired up |
| `scenes/effects/burning_trail_old.tscn` | 1.3 KB | **added 2026-07-17** — new but not yet wired up |
| `graphics/enemies/boss_c_director_missile.png` | 1.2 KB | **added 2026-07-09** — new but not yet wired up |
| `graphics/enemies/boss_c_director_bay_lifts.png` | 1.2 KB | **added 2026-07-09** — new but not yet wired up |
| `scripts/enemies/shoot_patterns/pair_shot.gd` | 1.2 KB | self-documented "preserved" in its header |
| `scenes/effects/engine_glow.tscn` | 0.5 KB | **added 2026-07-14** — new but not yet wired up |
| `shaders/multiply2.gdshader` | 0.5 KB | **added 2026-07-14** — new but not yet wired up |
| `scenes/dev/ui_designer.tscn` | 0.3 KB | Scene for the CLAUDE.md-cited tuner template. |

## Scope / exclusions

- **`tools/` (266 files)** — excluded. These are manually-run capture/test/validate
  scripts (the documented workflow), not engine-reachable by design. Many are one-shots for retired
  features and could be pruned in a separate pass.
- **`addons/`** — installed third-party plugins (godot_mcp, PixelPlanets, Ovani music). Keep.
- **False positives ruled out this run:** `default_bus_layout.tres` (Godot loads it implicitly when
  `[audio]` omits a `bus_layout` key), and all `assets/audio/music/**` (referenced by
  `resources/music/music_library.tres` via paths containing spaces).
- **Verified reachable:** all new stronghold, ground-building, drone, wave-pattern-editor and
  building-shadow work from the last two weeks.
