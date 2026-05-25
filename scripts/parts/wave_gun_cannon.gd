extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Wave Gun. Wide multi-hit energy wave. Lower per-shot damage but each
# bullet pierces up to 5 enemies on its way up the screen — strong
# against tight enemy formations, weaker against single elites.

@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var base_cooldown: float = 0.30

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: int = WS.WeaponStyle.ENERGY
var _prev_sfx_kind: String = ""

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Wave Gun"
	description = "Pierces up to 5 enemies in a line. Slow cadence, multi-hit."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = WS.WeaponStyle.ENERGY
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	if "fire_sfx_kind" in ship:
		_prev_sfx_kind = ship.fire_sfx_kind
		ship.fire_sfx_kind = "pulse"
	ship.cooldown = base_cooldown
	# Roman, 2026-05-18 weapon damage audit: wave gun was one-shotting
	# bosses at high Mk because base_damage × mark × max_hits stacked.
	# Halve the mark scaling so the wave is a 1-5 dmg per-enemy weapon
	# across its Mk.1-9 range (was 1-9). Multi-hit still rewards groups,
	# but bosses no longer evaporate to a single shot.
	ship.bullet_damage = int(max(1.0, base_damage * (1.0 + 0.5 * (mark_multiplier() - 1.0))))
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
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


# Wave gun uses multiplicative Mk scaling, not the standard additive
# formula. Mirror the math in apply() so the weapon editor's DPS
# readout matches in-game damage.
func effective_damage(at_mark: int) -> int:
	return int(max(1.0, float(base_damage) * (1.0 + 0.5 * (float(at_mark) - 1.0))))
