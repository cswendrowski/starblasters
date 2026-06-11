extends "res://scripts/parts/primary_weapon.gd"

# Wave Gun. Wide piercing energy wave. Slow + weak at Mk.1, ramps to a
# fast, fat-sprite pulse at Mk.9. All knobs (damage, ROF, projectile
# speed, pierce, sprite scene) scale with Mk per the 2026-05-24 rework
# spec:
#
#                       Mk.1     Mk.5     Mk.9
#   base_damage          4        8        12
#   base_cooldown (s)    0.708    ~0.41    ~0.25   (compound 1.15^(mk-1))
#   bullet_speed (px/s)  300      450      600
#   max_hits (pierce)    1        4        4 (cap)
#   bullet_scene         small    large    large
#
# Showcase test case for the WeaponPart declarative Mk-knob system —
# damage/cooldown/speed/max_hits all flow through _mk_knobs, bullet_scene
# uses a Callable picker for the small→large switch at Mk.5.

const BulletWaveSmall = preload("res://scenes/projectiles/bullet_wave_small.tscn")
const BulletWaveLarge = preload("res://scenes/projectiles/bullet_wave_large.tscn")

# Mk.9 endpoints (Mk.1 reads from base_*). Exposed for .tres tuning.
@export var damage_at_mk9: int = 12
@export var cooldown_at_mk9: float = 0.30
@export var bullet_speed_at_mk1: float = 300.0
@export var bullet_speed_at_mk9: float = 600.0


func _init() -> void:
	super._init()
	display_name = "Wave Gun"
	description = "Pierces enemies in a line. Mk.1 fires a small slow wave (dmg 4); Mk.9 punches a wide multi-hit pulse (dmg 12, fast)."
	base_damage = 4
	dmg_per_mark = 0  # not used — _mk_knobs encodes the curve directly
	base_cooldown = 0.708


func _fire_sfx_kind() -> int:
	# Default (Mk.1-4, small wave). _apply_visuals swaps to WAVE_BIG at Mk.5+.
	return WS.FireSfxKind.WAVE


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("bullet_speed_override")
	keys.append("bullet_max_hits_override")
	return keys


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": Callable(self, "_wave_damage_for_mark"),
		"cooldown": Callable(self, "_cooldown_for_mark"),
		"bullet_speed_override": [bullet_speed_at_mk1, bullet_speed_at_mk9],
		"bullet_max_hits_override": Callable(self, "_max_hits_for_mark"),
		"bullet_scene": Callable(self, "_scene_for_mark"),
	}


func _wave_damage_for_mark(at_mark: int) -> int:
	# Mk.1 = 4, Mk.2 = 5, ..., Mk.9 = 12. Linear +1/mark.
	return 3 + clampf(at_mark, 1, 9)


func _cooldown_for_mark(_at_mark: int) -> float:
	# FLAT ROF (Roman 2026-06-11): every mark fires at the old Mk.9 cadence
	# (0.708 / 1.15^8 ≈ 0.231s). Damage / projectile speed / pierce / sprite still
	# scale per mark — only the fire rate is flattened to the fast end.
	return 0.708 / pow(1.15, 8.0)


func _scene_for_mark(at_mark: int) -> PackedScene:
	# Designer-pinned .tres bullet_scene wins only if explicitly set on the
	# resource. Otherwise pick per-Mk: small below Mk.5, large from Mk.5.
	if bullet_scene != null:
		return bullet_scene
	return BulletWaveLarge if at_mark >= 5 else BulletWaveSmall


# bullet_scene is driven by the Mk-knob picker — skip the base class's
# @export write so a .tres-pinned scene doesn't bypass the Mk.5 switch.
func _apply_visuals(ship) -> void:
	ship.weapon_style = _weapon_style()
	# Single wave audio set for every mark now (Roman 2026-06-09: no Mk.5 audio swap).
	# The projectile still upgrades at Mk.5 (_scene_for_mark) — only the sound is unified.
	ship.fire_sfx_kind = WS.FireSfxKind.WAVE


func _max_hits_for_mark(at_mark: int) -> int:
	# Mk.1=1 → Mk.5=4 (linear over the lower band), then clamps at 4.
	if at_mark >= 5:
		return 4
	var t: float = (clampf(float(at_mark), 1.0, 5.0) - 1.0) / 4.0
	return int(round(lerpf(1.0, 4.0, t)))


# Weapon editor DPS readout — match the _mk_knobs damage curve.
func effective_damage(at_mark: int) -> int:
	return _wave_damage_for_mark(at_mark)
