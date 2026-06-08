extends "res://scripts/enemies/enemy_base.gd"

# Bulwark v2 (Roman 2026-05-18 redesign). Slow, chunky, shielded enemy
# that holds the center of the screen as a barrier. Uncommon-tough class
# with 2× the normal shield charges and self-regenerating shield (like
# the player). Inertial-thrust movement aimed at the screen center, not
# the player. Weak weapon — it's a tank, not a damage dealer.
#
# Sprite: tiny_ship11 at 1× scale (set in scene). Shield ring matches
# the player's shield visual so the player understands "this thing eats
# bullets the same way I do."

# --- Stats --------------------------------------------------------------
@export var shield_charges_max: int = 4        # 2× uncommon-tough baseline
@export var shield_recharge_interval: float = 6.0
@export var fire_interval_min: float = 2.3
@export var fire_interval_max: float = 3.2
@export var bullet_speed: float = 180.0

# --- Movement (inertial drift toward screen center) ---------------------
@export var move_speed_max: float = 60.0
@export var accel: float = 90.0
@export var center_target: Vector2 = Vector2(240, 90)
@export var arrive_radius: float = 12.0

var _vel: Vector2 = Vector2.ZERO

signal hull_changed(max_hull, hull)


func _ready() -> void:
	if max_health <= 1:
		max_health = 8        # uncommon-tough HP
	if bounty_value <= 0:
		bounty_value = 75
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	# Unified shield (shield_unification_2026-06-08.md): a regenerating CHARGE
	# ShieldComponent (its own ring) replaces the old bespoke _shield/ring/regen.
	# Appended BEFORE super._ready() so _init_components dups it per-instance.
	var sh := ShieldComponent.new()
	sh.capacity = shield_charges_max
	sh.regen_interval = shield_recharge_interval
	sh.ring_size = 48.0
	# Reassign (not append) — an @export Array default is shared across instances, so
	# appending would accumulate shields across spawns (mirrors factions.gd's pattern).
	components = components + [sh]
	super._ready()
	hull_changed.emit(max_health, health)
	var t := EnemyTurret.new()
	t.name = "Turret"
	t.position = Vector2(0, -4)
	t.rotation_speed    = 1.6
	t.fire_interval_min = fire_interval_min
	t.fire_interval_max = fire_interval_max
	t.aim_tolerance_deg = 30.0
	t.bullet_speed      = bullet_speed
	add_child(t)


# Hull shim — engine_torch / damage_smoke_trail look for these.
var hull: int:
	get:
		return health
	set(value):
		health = value
var max_hull: int:
	get:
		return max_health
	set(value):
		max_health = value


# Shield absorption now lives in the ShieldComponent (the damage pipeline runs it in
# enemy_base.take_hit via _components_hit). This override only re-emits hull_changed so the
# damage tells (engine torch / smoke) re-evaluate after every hit.
func take_hit(damage: int = 1) -> bool:
	var was_killed: bool = super.take_hit(damage)
	hull_changed.emit(max_health, health)
	return was_killed


func _process(delta: float) -> void:
	if _dying:
		return
	# Bulwark extends enemy_base (not enemy_core), so it must tick components itself —
	# this drives the ShieldComponent's regen (shield_unification_2026-06-08.md).
	_tick_components(delta)
	# Inertial thrust toward the center. Decelerates as it nears the
	# target so it settles without overshoot — chunky and deliberate.
	var to_target: Vector2 = center_target - position
	var dist: float = to_target.length()
	var desired_vel: Vector2 = Vector2.ZERO
	if dist > arrive_radius:
		desired_vel = to_target.normalized() * move_speed_max
	_vel = _vel.move_toward(desired_vel, accel * delta)
	position += _vel * delta
	# Shield regeneration is owned by the ShieldComponent (on_process). EnemyTurret child
	# handles aiming + firing.
