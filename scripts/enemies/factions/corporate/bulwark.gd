extends "res://scripts/enemies/enemy_core.gd"

# Bulwark v2 (Roman 2026-05-18 redesign; on-lane migration 2026-06-08). Slow,
# chunky, shielded enemy that holds a lane in the upper band as a barrier.
# Uncommon-tough class with 2× the normal shield charges and self-regenerating
# shield (like the player). Weak weapon — it's a tank, not a damage dealer.
#
# MOVEMENT: now on the lane system (extends enemy_core). The conductor assigns it
# a movement pattern via the eligibility matrix (drift_mid: descend to hover then
# jiggle-hold in its lane). The old bespoke inertial-thrust-to-screen-center was
# replaced by the shared Drift pattern — a lane-relative hold reads as a barrier
# wherever the conductor places it, and keeps it on the modular movement axis.
#
# Sprite: tiny_ship11 at 1× scale (set in scene). Shield ring matches
# the player's shield visual so the player understands "this thing eats
# bullets the same way I do."

const Drift = preload("res://scripts/enemies/patterns/drift.gd")

# --- Stats --------------------------------------------------------------
# NOTE: fire_interval_min/max are inherited from enemy_core (don't redeclare — that's a
# parse error). They drive enemy_core's ShootTimer, but this enemy fires via its EnemyTurret
# child instead, so we just set them in _ready and forward them to the turret.
@export var shield_charges_max: int = 4        # 2× uncommon-tough baseline
@export var shield_recharge_interval: float = 6.0
@export var bullet_speed: float = 180.0

signal hull_changed(max_hull, hull)


func _ready() -> void:
	if max_health <= 1:
		max_health = 8        # uncommon-tough HP
	if bounty_value <= 0:
		bounty_value = 75
	fire_interval_min = 2.3   # turret fire cadence (inherited enemy_core fields)
	fire_interval_max = 3.2
	auto_rotate = false       # the turret aims; the hull holds a fixed facing
	offscreen_mode = OffscreenMode.NONE   # a barrier holds its lane; never recycles
	# Fallback movement when spawned outside the conductor (dev tools / direct
	# instantiation). In production the director overwrites this with the matrix's
	# assigned pattern (drift_mid). Guarantees movement != null so enemy_core never
	# falls into the legacy anchor path (this scene has no MoveTimer/ShootTimer).
	if movement == null:
		var d := Drift.new()
		d.hover_y = 90.0
		movement = d
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

# Movement + component ticking are owned by enemy_core._process (drives the Drift
# pattern + ShieldComponent regen). The EnemyTurret child handles aiming + firing.
