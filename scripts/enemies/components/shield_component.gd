class_name ShieldComponent
extends EnemyComponent

# Regenerating charge-shield (player / bulwark style): absorbs hits one charge at a
# time and regenerates over time. The HP-unify vehicle (m6 §1.2/§3) — the single shared
# implementation that replaces the bespoke regen shields reimplemented on bulwark,
# sapper, and bosses. Mirrors bulwark.gd's ring + regen so converting bulwark is a
# drop-in (set max_shield=0, add this component).
#
# DISTINCT from enemy_base's simple `max_shield` charge-shield (used by chaff): that one
# is per-hit pips with no regen and is consumed in take_hit BEFORE components. This one
# regenerates and carries its own ring visual. An enemy uses one or the other, not both.

const SHIELD_SHADER = preload("res://graphics/sci_fi_shield.gdshader")
const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")

# The single shared enemy shield (shield_unification_2026-06-08.md). Two modes:
#   CHARGE — per-HIT charge shield: each hit spends one charge regardless of damage
#            magnitude (chaff/corporate/bulwark/bomber). regen_interval > 0 regens;
#            regen_interval <= 0 means NO regen (chaff + sector-modifier shields).
#   POOL   — a banked DAMAGE pool (the sapper): absorbs a damage AMOUNT, can grow past
#            `capacity` via bank() (stolen player shields), never regenerates. The only
#            mode that can "tank N damage" — what lets a well-fed sapper survive a bomb.
enum Mode { CHARGE, POOL }

@export var mode: int = Mode.CHARGE
@export var capacity: int = 3
@export var regen_interval: float = 6.0   # seconds to regenerate one CHARGE; <= 0 = no regen
@export var ring_size: float = 32.0

var _charges: int = 0
var _pool: float = 0.0   # POOL mode: banked damage capacity
var _regen_t: float = 0.0
var _ring: ColorRect = null
var _mat: ShaderMaterial = null
var _hit_tween: Tween = null


func on_start(enemy) -> void:
	if mode == Mode.POOL:
		_pool = float(capacity)
	else:
		_charges = capacity
	_regen_t = 0.0
	if _ring == null or not is_instance_valid(_ring):
		_build_ring(enemy)
	_update_visual()


# Bank stolen shield into the POOL (sapper steal). No-op in CHARGE mode.
func bank(amount: float) -> void:
	if mode != Mode.POOL:
		return
	_pool += max(0.0, amount)
	_update_visual()


func remaining_pool() -> float:
	return _pool


func is_pool() -> bool:
	return mode == Mode.POOL


# Absorb the hit. Returns the REMAINING damage (0 = fully absorbed, > 0 = passed to hull).
#   CHARGE: one charge per hit, fully consumes the hit while charged.
#   POOL:   absorbs min(damage, pool); remainder (rounded up) goes to hull.
func on_hit(enemy, damage: int) -> int:
	if mode == Mode.POOL:
		if _pool <= 0.0:
			return damage
		var absorbed: float = minf(float(damage), _pool)
		_pool -= absorbed
		_pulse()
		_update_visual()
		if enemy.has_node("Sprite2D"):
			HitFlashFx.flash(enemy.get_node("Sprite2D"), HitFlashFx.FLASH_SHIELD)
		return int(ceil(float(damage) - absorbed))
	if _charges <= 0:
		return damage
	_charges -= 1
	_regen_t = 0.0                      # taking a hit restarts the regen delay
	_pulse()
	_update_visual()
	if enemy.has_node("Sprite2D"):
		HitFlashFx.flash(enemy.get_node("Sprite2D"), HitFlashFx.FLASH_SHIELD)
	return 0


func on_process(_enemy, delta: float) -> void:
	# POOL never regenerates; CHARGE only when regen_interval > 0 (chaff/sector = no regen).
	if mode == Mode.POOL or regen_interval <= 0.0:
		return
	if _charges >= capacity:
		return
	_regen_t += delta
	if _regen_t >= regen_interval:
		_regen_t = 0.0
		_charges = mini(_charges + 1, capacity)
		_update_visual()


func on_death(_enemy) -> void:
	_free_ring()


func on_leave(_enemy) -> void:
	_free_ring()


func _build_ring(enemy) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHIELD_SHADER
	_mat.set_shader_parameter("alpha", 0.0)
	_mat.set_shader_parameter("hit_strength", 0.0)
	_ring = ColorRect.new()
	_ring.name = "ShieldRing"
	_ring.color = Color(1, 1, 1, 1)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(ring_size, ring_size)
	_ring.position = -_ring.size * 0.5
	_ring.material = _mat
	_ring.z_index = 1
	enemy.add_child(_ring)


func _update_visual() -> void:
	if _mat == null:
		return
	var lit: float = 0.0
	if mode == Mode.POOL:
		if _pool > 0.0:
			# Scale brightness with how full the pool is vs its initial capacity,
			# but never fully dark while any charge remains.
			lit = clampf(_pool / float(maxi(1, capacity)), 0.25, 1.0)
	elif _charges > 0:
		lit = clampf(float(_charges) / float(maxi(1, capacity)), 0.25, 1.0)
	_mat.set_shader_parameter("alpha", lit * 0.85)


func _pulse() -> void:
	if _mat == null or _ring == null or not is_instance_valid(_ring):
		return
	_mat.set_shader_parameter("hit_strength", 1.0)
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = _ring.create_tween()
	_hit_tween.tween_method(func(v): _mat.set_shader_parameter("hit_strength", v), 1.0, 0.0, 0.4)


func _free_ring() -> void:
	if _ring and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
