class_name BuildingBoom
extends RefCounted

# Per-building DEATH explosion — Roman's Shader Lab "Building Boom" tune (2026-07-17). Keyed by scene path →
# an ExplosionFx.play_config dict (type + size/area/density/duration/stagger/secondaries/glow/shockwave/
# sparks/debris). Wired into enemy_core_building_turret.explode(); the debris.png CHUNK scatter is a separate
# EnemyDeathFx.spawn_debris call there. Buildings without a CONFIG entry fall back to DEFAULT.
# Re-tune in Shader Lab "Building Boom" → Copy GDScript → paste the table back here.

const ExplosionFxC = preload("res://scripts/effects/explosion_fx.gd")

const DEFAULT := {"type": "basic", "size": 1.0, "area": 10.0, "duration": 0.07, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0}

const CONFIG := {
	"res://scenes/enemies/ground/b_b_glass.tscn": {"type": "basic", "size": 1.0, "area": 8.0, "duration": 0.07, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 1.0, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_b_glass_square.tscn": {"type": "basic", "size": 1.0, "area": 8.0, "duration": 0.07, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_f_bunker.tscn": {"type": "fireball", "size": 1.0, "area": 19.0, "duration": 0.06, "density": 8.0, "stagger": 0.05, "secondaries": 4.0, "glow": 0.9, "shockwave": 0.1, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_f_cross.tscn": {"type": "fireball", "size": 1.0, "area": 10.0, "duration": 0.05, "density": 8.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.1, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_f_tank.tscn": {"type": "fireball", "size": 1.0, "area": 7.0, "duration": 0.05, "density": 8.0, "stagger": 0.06, "secondaries": 1.5, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_s_hangar.tscn": {"type": "mixed", "size": 1.0, "area": 63.0, "duration": 0.07, "density": 12.0, "stagger": 0.1, "secondaries": 4.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.2, "debris": 3.0},
	"res://scenes/enemies/ground/b_s_glass.tscn": {"type": "ball", "size": 1.0, "area": 8.0, "duration": 0.055, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.3, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_p_small.tscn": {"type": "basic", "size": 0.6, "area": 8.0, "duration": 0.07, "density": 1.0, "stagger": 0.06, "secondaries": 0.0, "glow": 0.9, "shockwave": 0.0, "sparks": 0.6, "debris": 0.2},
	"res://scenes/enemies/ground/b_s_shed.tscn": {"type": "basic", "size": 1.0, "area": 16.0, "duration": 0.07, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_f_farm.tscn": {"type": "mixed", "size": 1.05, "area": 9.0, "duration": 0.07, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 3.0},
	"res://scenes/enemies/ground/b_t_twin.tscn": {"type": "basic", "size": 1.0, "area": 6.0, "duration": 0.065, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_t_scatter.tscn": {"type": "basic", "size": 1.0, "area": 8.0, "duration": 0.065, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_t_rocket.tscn": {"type": "basic", "size": 1.0, "area": 8.0, "duration": 0.06, "density": 3.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.9, "shockwave": 0.0, "sparks": 1.0, "debris": 2.0},
	"res://scenes/enemies/ground/b_t_ball.tscn": {"type": "basic", "size": 1.0, "area": 6.0, "duration": 0.05, "density": 1.0, "stagger": 0.06, "secondaries": 1.0, "glow": 0.5, "shockwave": 0.0, "sparks": 1.0, "debris": 1.0},
	"res://scenes/enemies/ground/b_t_wave.tscn": {"type": "basic", "size": 1.0, "area": 9.0, "duration": 0.07, "density": 2.0, "stagger": 0.06, "secondaries": 0.0, "glow": 0.7, "shockwave": 0.0, "sparks": 1.0, "debris": 2.0},
}


# Play a building's tuned death explosion (sparks + embers) at `world_pos` into `parent`. `size_mult` scales
# the boom for a director-scaled (huge/giant) spawn — pass the structure's display_scale (1.0 = as tuned).
static func play(scene_path: String, world_pos: Vector2, parent: Node, size_mult: float = 1.0) -> void:
	var cfg: Dictionary = CONFIG.get(scene_path, DEFAULT)
	if not is_equal_approx(size_mult, 1.0):
		cfg = cfg.duplicate()
		cfg["size"] = float(cfg["size"]) * size_mult
	ExplosionFxC.play_config(world_pos, cfg, parent)
