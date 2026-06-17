extends "res://scripts/enemies/enemy_core.gd"

# Omni Gunship (privateer). A vector-thrust harasser that roams the playfield holding a stand-off
# range (movement = "omni" from the roster slot) while working two weapons.
#
# Firing is now DATA-DRIVEN via the roster `mounts` key (EnemyRoster.GUNSHIP_MOUNTS — migrated from
# bespoke code 2026-06-16): an alternating-muzzle MG burst (Muzzle*, spread_pellet, aimed, 3-shot
# bursts) and dual wingtip cannons (Cannon*, heavy_slug, straight down). MountBuilder realizes them
# as MountComponents at spawn; this script keeps only the stat identity + locomotion (the omni
# movement pattern). The rocket variant (enemy_rocket.gd) shares this scene's launch-point rack.
#
# Two-frame sprite: frame 0 hull + frame 1 emissive glow (GlowMask). EnemyBase installs the damage
# shader on "Sprite2D" only, so the glow stays bright.

func _ready() -> void:
	max_health = 12
	bounty_value = 30
	super._ready()
