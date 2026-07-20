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
#
# The ring look is the shared ShieldRingFx driver (2026-07-09), identical to the player's:
# Sparse Plates base, charge-fraction fill/flicker, white hit-flash, collapse on break.
# Colour = the enemy's FACTION laser-inner (so enemy shields read as "not yours"); the sapper
# (POOL mode) is the exception — it shows the player cyan because its pool IS stolen player shield.

const SHIELD_SHADER = preload("res://graphics/hex_shield.gdshader")  # committed (Roman 2026-06-11)
const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")
const ShieldSfxC = preload("res://scripts/effects/shield_sfx.gd")
const ShieldRingFxC = preload("res://scripts/effects/shield_ring_fx.gd")
const FactionsC = preload("res://scripts/levels/factions.gd")
const ShieldFitC = preload("res://scripts/enemies/components/shield_fit.gd")

# Enemy hit-flash hold (enemies have no i-frames; a fixed brief hold before the resettle).
const HIT_HOLD := 0.12
# Collapse / come-online transition length.
const TRANSITION_SECS := 0.25

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
# Bubble roundness: 0 = a round dome; >0 stretches it into a taller vertical capsule so it hugs a
# longer (taller) enemy sprite. Tuned per-enemy in the Shader Lab "Enemy Shields" tab.
@export var elongation: float = 0.0
# Spawn with the shield DOWN (0 charges / empty pool) and raise it later via
# raise_shield(). Used by the Shielded Mine: a transition pageant plays, then the
# shield activates — a brief window to kill it unshielded.
@export var start_inactive: bool = false

var _charges: int = 0
var _pool: float = 0.0   # POOL mode: banked damage capacity
var _regen_t: float = 0.0
var _ring: ColorRect = null
var _mat: ShaderMaterial = null
var _fx = null           # ShieldRingFx driver (owns the look + tweens)
var _outer_shape: CollisionShape2D = null   # optional bubble-sized hitbox (see on_start)
var _use_size: float = 0.0                  # fit-resolved bubble size (set in _build_ring)
var _use_elong: float = 0.0


func on_start(enemy) -> void:
	if start_inactive:
		_pool = 0.0
		_charges = 0
	elif mode == Mode.POOL:
		_pool = float(capacity)
	else:
		_charges = capacity
	_regen_t = 0.0
	if _ring == null or not is_instance_valid(_ring):
		_build_ring(enemy)
	# Oversized-shield HITBOX (bulwark): an enemy whose bubble is meant to physically
	# block shots aimed PAST it authors a sibling CollisionShape2D named
	# "CollisionOuterShield". The component sizes it to the resolved bubble and keeps
	# it live only while the shield is up — with it down, only the hull shape takes hits.
	_outer_shape = enemy.get_node_or_null("CollisionOuterShield") as CollisionShape2D
	_fit_outer_shape()
	_update_visual()


# Raise a start_inactive shield to full (the Shielded Mine calls this when its
# activation transition completes). Safe to call any time.
func raise_shield() -> void:
	if mode == Mode.POOL:
		_pool = float(capacity)
	else:
		_charges = capacity
	_regen_t = 0.0
	_update_visual()


# Instantly drop the shield to zero (charges + pool) and refresh the ring visual. Used by the EM
# Torpedo burst, which STRIPS shields before applying its (shield-ignoring) damage (Roman 2026-06-10).
func break_shield() -> void:
	_charges = 0
	_pool = 0.0
	_regen_t = 0.0
	_update_visual()


# Bank stolen shield into the POOL (sapper steal). No-op in CHARGE mode.
func bank(amount: float) -> void:
	if mode != Mode.POOL:
		return
	_pool += max(0.0, amount)
	if _fx != null:
		_fx.pulse()   # "gulp" feedback as it eats a charge
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
		_update_visual()
		_flash(enemy)
		_play_absorb_sfx(enemy, _pool <= 0.0)
		return int(ceil(float(damage) - absorbed))
	if _charges <= 0:
		return damage
	_charges -= 1
	_regen_t = 0.0                      # taking a hit restarts the regen delay
	_update_visual()
	_flash(enemy)
	_play_absorb_sfx(enemy, _charges <= 0)
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
		if _fx != null:
			_fx.pulse()   # per-charge regen pulse
		_update_visual()


func on_death(_enemy) -> void:
	_free_ring()


func on_leave(_enemy) -> void:
	_free_ring()


func _build_ring(enemy) -> void:
	# Per-enemy shield FIT (Shader Lab "Enemy Shields" tab): a tuned size/roundness for THIS enemy scene
	# wins over the @export defaults, so every enemy's bubble hugs its own sprite.
	var fit: Dictionary = ShieldFitC.fit_for(String(enemy.scene_file_path))
	_use_size = float(fit.get("ring_size", ring_size))
	_use_elong = float(fit.get("elongation", elongation))
	_mat = ShaderMaterial.new()
	_mat.shader = SHIELD_SHADER
	_ring = ColorRect.new()
	_ring.name = "ShieldRing"
	_ring.color = Color(1, 1, 1, 1)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(_use_size, _use_size)
	_ring.position = -_ring.size * 0.5
	_ring.material = _mat
	_ring.z_index = 1
	enemy.add_child(_ring)
	_fx = ShieldRingFxC.new(_mat, _ring, _pick_color(enemy))
	_mat.set_shader_parameter("elongation", _use_elong)   # per-enemy bubble roundness (Shader Lab tuned)


# Size the authored CollisionOuterShield to the fit-resolved bubble so hitbox == visual.
# The hex_shield bubble fills its rect: circle radius = size/2; elongation > 0 makes a
# vertical capsule of half-width (1 - elongation) * size/2 and full height = size.
func _fit_outer_shape() -> void:
	if _outer_shape == null:
		return
	if _outer_shape.shape is CapsuleShape2D:
		var cap := _outer_shape.shape as CapsuleShape2D
		cap.radius = maxf(1.0 - _use_elong, 0.05) * _use_size * 0.5
		cap.height = _use_size
	elif _outer_shape.shape is CircleShape2D:
		(_outer_shape.shape as CircleShape2D).radius = _use_size * 0.5


# The sapper (POOL) shows the player cyan (its pool is stolen player shield); every other enemy
# shield takes its faction's laser-inner colour (white fallback for un-factioned units).
func _pick_color(enemy) -> Color:
	if mode == Mode.POOL:
		return ShieldRingFxC.PLAYER_COLOR
	return FactionsC.muzzle_inner(int(enemy.get_meta("faction_skin", -1)))


func _fraction() -> float:
	var denom: float = float(maxi(1, capacity))
	if mode == Mode.POOL:
		return clampf(_pool / denom, 0.0, 1.0)
	return clampf(float(_charges) / denom, 0.0, 1.0)


func _shield_up() -> bool:
	return _pool > 0.0 if mode == Mode.POOL else _charges > 0


func _update_visual() -> void:
	# The outer hitbox tracks shield state 1:1 — live only while charges/pool remain.
	# Deferred: hits arrive inside physics callbacks where flipping shapes is blocked.
	if _outer_shape != null and is_instance_valid(_outer_shape):
		_outer_shape.set_deferred("disabled", not _shield_up())
	if _fx == null:
		return
	_fx.apply_state(_fraction())
	_fx.set_online(_shield_up(), TRANSITION_SECS)


# Shared shield hit/break clips (same pool as the player's shield, 2026-07-14) —
# break plays on the hit that empties the charges/pool, hit otherwise. Positional.
func _play_absorb_sfx(enemy, broke: bool) -> void:
	if enemy == null or not enemy.is_inside_tree():
		return
	if broke:
		ShieldSfxC.play_break(enemy.get_tree().root, enemy.global_position)
	else:
		ShieldSfxC.play_hit(enemy.get_tree().root, enemy.global_position)


func _flash(enemy) -> void:
	if _fx != null:
		_fx.hit_flash(_fraction(), HIT_HOLD)
	if enemy.has_node("Sprite2D"):
		HitFlashFx.flash(enemy.get_node("Sprite2D"), HitFlashFx.FLASH_SHIELD)


func _free_ring() -> void:
	if _ring and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	_fx = null
	if _outer_shape != null and is_instance_valid(_outer_shape):
		_outer_shape.set_deferred("disabled", true)
	_outer_shape = null
