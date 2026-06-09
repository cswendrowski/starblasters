extends "res://scripts/enemy_core.gd"

# Gravity Mine (Roman 2026-06-09) — replaces the Cluster + Mega Cluster mines. Drifts down like
# any mine, ringed by 4/6/8 real Bomblets slowly orbiting it (1 px/f tangential, CW or CCW). The
# bomblets are hittable + killable on their own; on the mine's death (or off-screen exit) the
# survivors are RELEASED, inheriting the mine's drift PLUS the tangential velocity of their orbit.
# Same hull as the Armored Mine (4 HP). Carries the #c73bff gravity glow (glowmask frame) + the
# shared red centre blink.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const GravityGlow = preload("res://scripts/effects/gravity_glow.gd")
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")
const BombletScene = preload("res://scenes/enemies/enemy_bomblet.tscn")

@export var drift_speed: float = 100.0
@export var damage_on_collide: int = 2
@export var hull_hp: int = 4                       # same as the Armored Mine
@export var orbit_radius: float = 18.0
@export var orbit_tangential_speed: float = 60.0   # 1 px/f

var _bomblets: Array = []      # [{node, offset}]
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0    # +1 / -1 = CW / CCW
var _omega: float = 0.0        # rad/s = tangential / radius


func _ready() -> void:
	max_health = hull_hp
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false
	recycle_passes = 0
	if has_node("Sprite2D"):
		$Sprite2D.frame = 0
	if movement == null:
		var m := StraightDown.new()
		m.speed = drift_speed
		movement = m
	super._ready()
	# #c73bff gravity glow (glowmask frame, always on) + the shared red centre blink.
	if has_node("Sprite2D"):
		var g := GravityGlow.new()
		add_child(g)
		g.setup($Sprite2D)
	add_child(MineBlinker.new())
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_omega = orbit_tangential_speed / maxf(orbit_radius, 1.0)
	_orbit_angle = randf() * TAU
	_spawn_bomblets()


func _spawn_bomblets() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var n: int = [4, 6, 8][randi() % 3]
	for i in n:
		var b = BombletScene.instantiate()
		# Siblings in the world (not children) so they survive the mine's free; the mine drives
		# their position while orbiting.
		parent.add_child(b)
		if b.has_method("set_orbiting"):
			b.set_orbiting(true)
		_bomblets.append({"node": b, "offset": TAU * float(i) / float(n)})
	_position_bomblets()


func _process(delta: float) -> void:
	super._process(delta)   # StraightDown drift + components
	if _dying:
		return
	_orbit_angle += _omega * _orbit_dir * delta
	_position_bomblets()


func _position_bomblets() -> void:
	var live: Array = []
	for e in _bomblets:
		var b = e["node"]
		if b == null or not is_instance_valid(b) or b._dying:
			continue
		var ang: float = _orbit_angle + float(e["offset"])
		b.global_position = global_position + Vector2(cos(ang), sin(ang)) * orbit_radius
		live.append(e)
	_bomblets = live


# Free the surviving bomblets into the world with their inherited velocity (mine drift + tangential
# orbit velocity). Idempotent — clears the list so a later _exit_tree is a no-op.
func _release_bomblets() -> void:
	var mine_vel := Vector2(0.0, drift_speed)
	for e in _bomblets:
		var b = e["node"]
		if b == null or not is_instance_valid(b) or b._dying or not b.has_method("release"):
			continue
		var ang: float = _orbit_angle + float(e["offset"])
		var tangential := Vector2(-sin(ang), cos(ang)) * _orbit_dir * orbit_tangential_speed
		b.release(mine_vel + tangential)
	_bomblets = []


func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()


func explode() -> void:
	if _dying:
		return
	_release_bomblets()
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.burst(global_position, 2, 8.0, 0.05)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


# Catch-all: if the mine is freed for ANY reason (off-screen, level wipe), don't strand the
# orbiting bomblets frozen in space — release them so they drift + despawn normally.
func _exit_tree() -> void:
	if not _bomblets.is_empty():
		_release_bomblets()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
