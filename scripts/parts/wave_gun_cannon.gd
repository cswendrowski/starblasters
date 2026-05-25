extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Wave Gun. Wide piercing energy wave. Slow + weak at Mk.1, ramps to a
# fast, fat-sprite pulse at Mk.9. All knobs (damage, ROF, projectile
# speed, pierce, sprite scene) scale with Mk per the 2026-05-24 rework
# spec:
#
#                       Mk.1     Mk.5     Mk.9
#   base_damage          1        3        5
#   base_cooldown (s)    0.85     0.55     0.35
#   bullet_speed (px/s)  600      900      1200
#   max_hits (pierce)    1        4        4 (cap)
#   bullet_scene         small    large    large
#
# Linear interpolation across Mk.1–9 except for max_hits which clamps at
# 4 from Mk.5 onward. bullet_scene switches to bullet_wave_large at Mk.5.

const BulletWaveSmall = preload("res://scenes/projectiles/bullet_wave_small.tscn")
const BulletWaveLarge = preload("res://scenes/projectiles/bullet_wave_large.tscn")

# Designer-tunable knobs (overridden by .tres). Kept in sync with the
# table above so the editor's DPS readout matches in-game behavior.
@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var base_cooldown: float = 0.85

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: int = WS.WeaponStyle.ENERGY
var _prev_sfx_kind: String = ""
var _prev_bullet_speed_override: float = -1.0
var _prev_bullet_max_hits_override: int = -1

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Wave Gun"
	description = "Pierces enemies in a line. Slow and weak at Mk.1, fattens to a wide multi-hit pulse at higher Mks."

# Linear interpolation Mk.1 → Mk.9 helper. Mk clamps to [1,9].
func _lerp_mk(at_mk1: float, at_mk9: float) -> float:
	var m: float = clampf(float(mark), 1.0, 9.0)
	var t: float = (m - 1.0) / 8.0
	return lerpf(at_mk1, at_mk9, t)

func _scene_for_mark() -> PackedScene:
	return BulletWaveLarge if int(mark) >= 5 else BulletWaveSmall

func _damage_for_mark() -> int:
	# Mk.1 = 1, Mk.5 = 3, Mk.9 = 5 → linear (1 + 0.5*(Mk-1)).
	return int(round(_lerp_mk(1.0, 5.0)))

func _cooldown_for_mark() -> float:
	# Mk.1 = 0.85s, Mk.9 = 0.35s.
	return _lerp_mk(0.85, 0.35)

func _bullet_speed_for_mark() -> float:
	# Mk.1 = 600 px/s, Mk.9 = 1200 px/s.
	return _lerp_mk(600.0, 1200.0)

func _max_hits_for_mark() -> int:
	# Mk.1 = 1, ramps to 4 at Mk.5+ (cap).
	if int(mark) >= 5:
		return 4
	# Mk.1 → 1, Mk.5 → 4 (linear over the lower band).
	var m: float = clampf(float(mark), 1.0, 5.0)
	var t: float = (m - 1.0) / 4.0
	return int(round(lerpf(1.0, 4.0, t)))

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = WS.WeaponStyle.ENERGY
	if "fire_sfx_kind" in ship:
		_prev_sfx_kind = ship.fire_sfx_kind
		ship.fire_sfx_kind = "pulse"
	# Bullet scene: small (<Mk.5) or large (>=Mk.5). The @export wins only
	# if the designer pinned a specific scene in the .tres; otherwise we
	# select per Mk.
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	else:
		ship.bullet_scene = _scene_for_mark()
	ship.cooldown = _cooldown_for_mark()
	ship.bullet_damage = _damage_for_mark()
	if "bullet_speed_override" in ship:
		_prev_bullet_speed_override = ship.bullet_speed_override
		ship.bullet_speed_override = _bullet_speed_for_mark()
	if "bullet_max_hits_override" in ship:
		_prev_bullet_max_hits_override = ship.bullet_max_hits_override
		ship.bullet_max_hits_override = _max_hits_for_mark()
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


func unapply(ship) -> void:
	ship.bullet_scene = _prev_bullet_scene
	ship.cooldown = _prev_cooldown
	ship.bullet_damage = _prev_damage
	if "weapon_style" in ship:
		ship.weapon_style = _prev_style
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = _prev_sfx_kind
	if "bullet_speed_override" in ship:
		ship.bullet_speed_override = _prev_bullet_speed_override
	if "bullet_max_hits_override" in ship:
		ship.bullet_max_hits_override = _prev_bullet_max_hits_override
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


# Weapon editor DPS readout uses this hook to surface the actual scaled
# damage at the given Mk instead of the base_damage @export.
func effective_damage(at_mark: int) -> int:
	var m: float = clampf(float(at_mark), 1.0, 9.0)
	var t: float = (m - 1.0) / 8.0
	return int(round(lerpf(1.0, 5.0, t)))
