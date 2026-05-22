extends "res://scripts/enemies/enemy_base.gd"

# Shielded Mine variant. Behavior is identical to a regular mine once the
# shield is broken; the shield phase is a per-hit absorber that doesn't
# count against the mine's health budget.

# Tuned so the bullet pipeline keeps calling hit() while the shield is up.
# Flow: 1st bullet raises the shield + 2 absorbed by shield + 1 activates +
# 1 kills = 5 total bullets.
# 320×400 res rework — speeds halved.
@export var drift_speed: float = 78.0  # +20% per Roman 2026-05-18
@export var damage_on_collide: int = 2
@export var shield_health: int = 2
# Roman, 2026-05-18 mine pass: shielded mine is a 3-frame strip
# (F0 dormant → F1 transition → F2 shielded). It doesn't chase; the
# shield is the upgrade, not motility.
# Was 8.0 — too small to render outside the mine sprite, so the shield
# was effectively invisible (Roman 2026-05-19 "shielded mines activated
# but didn't have a shield effect"). Bumped to 24 so the ring sits
# clearly around the mine.
const SHIELD_RING_SIZE := 24.0

var _shield: int = 0
var _shield_up: bool = false
var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	max_health = 5
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	if has_node("Sprite2D"):
		# Shield is up from spawn now (Roman 2026-05-19 "1 charge = 1 hit
		# negated mechanic like the player"). Skip the F0/F1 activation
		# pageant and just sit on the shielded frame.
		$Sprite2D.hframes = 3
		$Sprite2D.frame = 2
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)
	_setup_shield_ring()
	_shield_up = true
	_shield = shield_health
	if _shield_mat:
		_shield_mat.set_shader_parameter("alpha", 0.85)


func _setup_shield_ring() -> void:
	# Same sci-fi shield material the player uses, sized to wrap the mine
	# sprite. Hidden (alpha 0) at start; raised when the mine takes its
	# first hit, depleted as further hits drain the shield budget.
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.0)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)
	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1)  # shader drives final color
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_ring.size = Vector2(SHIELD_RING_SIZE, SHIELD_RING_SIZE)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)


func _set_shield_alpha(target: float, duration: float) -> void:
	if _shield_mat == null:
		return
	if _shield_alpha_tween and _shield_alpha_tween.is_valid():
		_shield_alpha_tween.kill()
	if duration <= 0.0:
		_shield_mat.set_shader_parameter("alpha", target)
		return
	var current: float = float(_shield_mat.get_shader_parameter("alpha"))
	_shield_alpha_tween = create_tween()
	_shield_alpha_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("alpha", v),
		current, target, duration
	)


func _pulse_shield_hit() -> void:
	if _shield_mat == null:
		return
	if _shield_hit_tween and _shield_hit_tween.is_valid():
		_shield_hit_tween.kill()
	_shield_mat.set_shader_parameter("hit_strength", 1.0)
	_shield_hit_tween = create_tween()
	_shield_hit_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("hit_strength", v),
		1.0, 0.0, 0.35
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func start(pos: Vector2) -> void:
	position = pos
	_velocity = Vector2(0.0, drift_speed)

func _process(delta: float) -> void:
	if _dying:
		return
	position += _velocity * delta
	if position.y > screensize.y + 32.0:
		queue_free()

func hit() -> void:
	var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
	# Shield is up from spawn — each hit consumes one charge; once
	# depleted, bullets deal normal damage (Roman 2026-05-19 player-style
	# 1-charge-1-hit mechanic).
	if _shield_up and _shield > 0:
		_shield -= 1
		_pulse_shield_hit()
		if has_node("Sprite2D"):
			HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_SHIELD)
		if has_node("ParticleHit"):
			$ParticleHit.restart()
		var ShieldSfx = load("res://scripts/effects/shield_sfx.gd")
		if _shield <= 0:
			_shield_up = false
			_set_shield_alpha(0.0, 0.25)
			if ShieldSfx:
				ShieldSfx.play_break(get_tree().root, global_position)
		else:
			if ShieldSfx:
				ShieldSfx.play_hit(get_tree().root, global_position)
		return
	# Shield down → flash + let bullet pipeline drop health normally.
	if has_node("Sprite2D"):
		HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_WHITE)
	if has_node("ParticleHit"):
		$ParticleHit.restart()

func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Kill the shield ring instantly so it doesn't linger over the explosion
	# (Roman, 2026-05-16: "shielded effect persists for a moment after the
	# enemy is killed; shield should vanish first").
	if _shield_alpha_tween and _shield_alpha_tween.is_valid():
		_shield_alpha_tween.kill()
	if _shield_hit_tween and _shield_hit_tween.is_valid():
		_shield_hit_tween.kill()
	if _shield_ring and is_instance_valid(_shield_ring):
		_shield_ring.visible = false
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
