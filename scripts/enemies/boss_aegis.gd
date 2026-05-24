extends "res://scripts/enemies/boss_base.gd"

# Aegis (formerly Sentinel) — sector 2-3 multi-part turret. Identity: the
# pylons. Two destructible pylon Area2Ds flank the core; while either
# pylon is alive, the core takes no damage. Phases auto-driven by pylon
# state (not HP%), so this boss bypasses the HP-gated phase machine.
#
# Stats set BEFORE super._ready() — no fallback pattern.

const MissileScene = preload("res://scenes/projectiles/drifting_missile.tscn")
const AegisPylonScript = preload("res://scripts/enemies/aegis_pylon.gd")

@export var pylon_hp: int = 80
@export var pylon_offset_x: float = 36.0

# State: "both", "one_down", "core_only"
var _pylon_state: String = "both"
var _left_pylon: Area2D = null
var _right_pylon: Area2D = null
var _missile_t: float = 0.0


func _ready() -> void:
	max_health = 240
	bounty_value = 350
	display_scale = 1.0
	boss_hover_y = 56.0
	fire_interval_min = 1.5
	fire_interval_max = 1.5
	# Empty phases — pylon-driven state machine handles the escalation.
	phases = []
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))
	_spawn_pylons()


func _spawn_pylons() -> void:
	_left_pylon = _make_pylon(-pylon_offset_x, "left")
	_right_pylon = _make_pylon(pylon_offset_x, "right")
	add_child(_left_pylon)
	add_child(_right_pylon)


func _make_pylon(local_x: float, side_name: String) -> Area2D:
	var pylon := Area2D.new()
	pylon.set_script(AegisPylonScript)
	pylon.name = "Pylon_" + side_name
	pylon.position = Vector2(local_x, 0)
	pylon.add_to_group("enemies")
	# Sprite — small placeholder square so the player sees what to hit.
	var spr := Sprite2D.new()
	spr.texture = preload("res://graphics/enemies/enemy_placeholder_16x.png")
	spr.modulate = Color(0.5, 1.0, 1.0, 1.0)
	spr.name = "Sprite2D"
	pylon.add_child(spr)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	cs.shape = shape
	pylon.add_child(cs)
	pylon.hp = pylon_hp
	pylon.max_hp = pylon_hp
	pylon.side = side_name
	pylon.pylon_killed.connect(_on_pylon_killed)
	return pylon


func _on_pylon_killed(_side: String) -> void:
	if _pylon_state == "both":
		_pylon_state = "one_down"
	elif _pylon_state == "one_down":
		_pylon_state = "core_only"
	_enrage_flash(Color(0.6, 1.0, 1.0, 1.0), 0.4)
	_screen_shake(4.0, 0.3)


# Override take_hit: while pylons survive, the core is invulnerable. Show
# a shield flash so the player reads "can't damage me yet".
func take_hit(damage: int = 1) -> bool:
	if _pylon_state != "core_only":
		# Flash blue and play shield hit; absorb damage entirely.
		if has_node("Sprite2D"):
			var spr := $Sprite2D as Sprite2D
			var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
			HitFlashFx.flash(spr, HitFlashFx.FLASH_SHIELD)
		var ShieldSfx = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfx:
			ShieldSfx.play_hit(get_tree().root, global_position)
		return false
	return super.take_hit(damage)


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		match _pylon_state:
			"both":
				# Pylons crossfire alternation — pick one of the two each tick.
				await get_tree().create_timer(1.8).timeout
				if _dying:
					return
				var alive: Array = []
				if is_instance_valid(_left_pylon):
					alive.append(_left_pylon)
				if is_instance_valid(_right_pylon):
					alive.append(_right_pylon)
				if alive.size() > 0:
					var pick: Area2D = alive[randi() % alive.size()]
					_fire_pylon_burst(pick)
			"one_down":
				await get_tree().create_timer(1.0).timeout
				if _dying:
					return
				var surv: Area2D = _left_pylon if is_instance_valid(_left_pylon) else _right_pylon
				if surv != null and is_instance_valid(surv):
					_fire_pylon_burst(surv, 5, 22.0)
			"core_only":
				await get_tree().create_timer(1.5).timeout
				if _dying:
					return
				fire_aimed_burst(7, 28.0)
				_missile_t += 1.5
				if _missile_t >= 3.5:
					_missile_t = 0.0
					_drop_missile_salvo()


func _fire_pylon_burst(pylon: Area2D, count: int = 3, spread_deg: float = 18.0) -> void:
	# Aim from the pylon's position toward the player.
	var p := find_player()
	if p == null or not (p is Node2D):
		return
	var origin: Vector2 = pylon.global_position
	var aim: Vector2 = ((p as Node2D).global_position - origin).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(0, 1)
	var spread_rad: float = deg_to_rad(spread_deg)
	for i in count:
		var t: float = 0.0
		if count > 1:
			t = (float(i) / float(count - 1)) * 2.0 - 1.0
		var dir: Vector2 = aim.rotated(t * spread_rad * 0.5)
		var bs := _bullet_scene()
		if bs == null:
			continue
		var b = bs.instantiate()
		get_tree().root.add_child(b)
		if b.has_method("start"):
			b.start(origin, dir)
		else:
			b.global_position = origin


func _drop_missile_salvo() -> void:
	const SALVO: int = 4
	for i in SALVO:
		var m = MissileScene.instantiate()
		get_parent().add_child(m)
		var t: float = 0.0
		if SALVO > 1:
			t = (float(i) / float(SALVO - 1)) * 2.0 - 1.0
		var spawn_pos: Vector2 = global_position + Vector2(t * 40.0, 40.0)
		if m.has_method("start"):
			m.start(spawn_pos)
		else:
			m.global_position = spawn_pos


func _on_boss_death() -> void:
	# Pylons free with the boss as children, but if either lingered as a
	# top-level node for some reason, clean up.
	if is_instance_valid(_left_pylon):
		_left_pylon.queue_free()
	if is_instance_valid(_right_pylon):
		_right_pylon.queue_free()
