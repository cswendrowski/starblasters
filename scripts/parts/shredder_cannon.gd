extends "res://scripts/parts/metered_primary.gd"

# Shredder — a space shotgun (CANNON-slot metered primary, Roman 2026-06-11). Fires a
# 6-pellet fan across a 25° cone at a steady cadence; each pellet deals 1 damage and
# wears the Swarm Launcher's visual (bullet_shredder.tscn) but flies dead straight.
#
# Mk ALTERNATES the two upgrade halves (ammo first):
#   Mk:   1    2    3    4    5    6    7    8    9
#   pellets 6  6    7    7    8    8    9    9   10   (+1 at 3,5,7,9)
#   ammo   60  72   72   86   86  104  104  124  124  (×1.2 at 2,4,6,8)
#
# Stats live in resources/weapons/shredder.tres (single source of truth).

const WSsh = preload("res://scripts/weapons/WeaponStyle.gd")
const BulletShredder = preload("res://scenes/projectiles/bullet_shredder.tscn")

@export var base_bullet_count: int = 6
@export var spread_degrees: float = 17.0   # narrowed from 25 (Roman 2026-06-11)


func _init() -> void:
	super._init()
	display_name = "Shredder"
	description = "Space shotgun — a 6-pellet fan in a 25° cone, light per pellet. Mk alternates +20% ammo and +1 pellet."
	if bullet_scene == null:
		bullet_scene = BulletShredder


# _weapon_style inherits the default (ENERGY) — the spread FAN is driven by
# bullet_spread_count, not the style (same as the Scatter Blaster). Style only
# routes SFX, and the fire-SFX kind below gives it the spread audio.
func _fire_sfx_kind() -> int:
	return WSsh.FireSfxKind.SPREAD


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("bullet_spread_count")
	keys.append("bullet_spread_degrees")
	keys.append("bullet_spread_random")   # restored to false when swapped away
	return keys


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [base_damage, base_damage],   # flat per-pellet damage (1)
		"cooldown": [base_cooldown, base_cooldown],
		"bullet_spread_count": Callable(self, "_count_for_mark"),
		"bullet_spread_degrees": [spread_degrees, spread_degrees],
	}


# +1 pellet at Mk 3,5,7,9 (the "add a bullet" half of the alternation).
func _count_for_mark(at_mark: int) -> int:
	return base_bullet_count + (clampi(at_mark, 1, 9) - 1) / 2


# ×1.2 max ammo at Mk 2,4,6,8 (the "+20% ammo" half). Mk.1=60 → Mk.9≈124.
func ammo_at_mark(mk: int) -> int:
	var steps: int = clampi(mk, 1, 9) / 2
	return int(round(float(base_ammo) * pow(1.2, float(steps))))


# Seed per-mark ammo BEFORE super (mirrors quad_lasers — metered_primary's base
# seeds flat base_ammo, so the per-mark magazine must be stamped here).
func _apply_visuals(ship) -> void:
	current_ammo = ammo_at_mark(int(mark))
	super._apply_visuals(ship)
	if "ammo_max" in ship:
		ship.ammo_max = ammo_at_mark(int(mark))
	# Shotgun: randomize each pellet's angle in the cone (snapshotted → restored on swap).
	if "bullet_spread_random" in ship:
		ship.bullet_spread_random = true


# Editor DPS readout — total per-shot damage accounts for the pellet fan.
func effective_damage(at_mark: int) -> int:
	return base_damage * _count_for_mark(at_mark)
