extends "res://scripts/enemies/enemy_base.gd"

# Cluster Mine. On hit, self-destructs and releases bomblets that drift
# around the playfield. `smart` + `bomblet_count` control whether bomblets
# home onto the player.

# Default to 4 bomblets per Roman's 2026-05-18 mine pass; mega cluster
# overrides to 8 via the enemy_mine_cluster_smart.tscn instance.
@export var drift_speed: float = 180.0  # +15% per Roman 2026-05-27 (was 156.0)
@export var damage_on_collide: int = 2
@export var bomblet_scene: PackedScene
@export var bomblet_count: int = 4
@export var bomblet_eject_speed: float = 200.0
@export var bomblet_smart: bool = false
# Proximity-arm radius. When the player crosses inside this distance,
# the cluster mine self-destructs without needing a bullet hit.
@export var proximity_trigger: float = 16.0

var _velocity: Vector2 = Vector2.ZERO
var _pulse_phase: float = 0.0
var _detonated: bool = false


func _ready() -> void:
	max_health = 1
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false  # no ground shadow / damage-overlay — mines explode, not fray
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_pulse_phase = randf() * TAU
	if bomblet_scene == null:
		bomblet_scene = load("res://scenes/enemies/enemy_bomblet.tscn")
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	position = pos
	_velocity = Vector2(0.0, drift_speed)


func _process(_delta: float) -> void:
	if _dying:
		return
	if has_node("Sprite2D") and not _detonated:
		var t: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.5 + 0.5 * sin(t * 4.5 + _pulse_phase)
		var k: float = 1.0 + 0.8 * pulse
		$Sprite2D.modulate = Color(k, 1.0, 1.0, 1.0)
	position += _velocity * _delta
	# Proximity trigger — self-destruct when the player crosses inside
	# `proximity_trigger` (Roman, 2026-05-18 mine pass).
	if not _detonated:
		var p := find_player()
		if p and is_instance_valid(p):
			if global_position.distance_to(p.global_position) <= proximity_trigger:
				_detonate()
	if position.y > screensize.y + 80.0:
		queue_free()


# Both hit() (non-fatal) and explode() (bullet-fatal) route through
# _detonate so the bomblet payload always fires regardless of which branch
# the bullet pipeline took.
func hit() -> void:
	_detonate()


func explode() -> void:
	if _dying:
		return
	if not _detonated:
		_detonated = true
		_spawn_bomblets()
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# Cluster mines pop a quick 2-blast burst rather than one bigger one.
	ExplosionFx.burst(global_position, 2, 6.0, 0.04)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.35)
	await get_tree().create_timer(0.35).timeout
	queue_free()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_spawn_bomblets()
	explode()


func _spawn_bomblets() -> void:
	if bomblet_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	for i in bomblet_count:
		var b = bomblet_scene.instantiate()
		if "smart" in b:
			b.smart = bomblet_smart
		var ang: float = TAU * (float(i) / float(bomblet_count)) + randf_range(-0.2, 0.2)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		# Bomblet scale is owned by bomblet.gd (display_scale=3.0). DON'T
		# override here — Roman, 2026-05-17 — otherwise minelayer and
		# cluster paths render at different sizes.
		parent.call_deferred("add_child", b)
		var scatter: Vector2 = Vector2(randf_range(-18.0, 18.0), randf_range(-14.0, 14.0))
		b.call_deferred("launch", global_position + scatter, dir, bomblet_eject_speed)


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		_detonate()
