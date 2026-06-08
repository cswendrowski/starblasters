extends "res://scripts/enemies/enemy_base.gd"

# Shielded Mine variant. Behavior is identical to a regular mine once the
# shield is broken; the shield phase is a per-hit absorber that doesn't
# count against the mine's health budget.

# Tuned so the bullet pipeline keeps calling hit() while the shield is up.
# Flow: 1st bullet raises the shield + 2 absorbed by shield + 1 activates +
# 1 kills = 5 total bullets.
# 320×400 res rework — speeds halved.
@export var drift_speed: float = 120.0  # +15% per Roman 2026-05-27 (was 78.0)
@export var damage_on_collide: int = 2
@export var shield_health: int = 2
# Roman, 2026-05-18 mine pass: shielded mine is a 3-frame strip
# (F0 dormant → F1 transition → F2 shielded). It doesn't chase; the
# shield is the upgrade, not motility.

var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	max_health = 5
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false  # no ground shadow / damage-overlay — mines explode, not fray
	offscreen_mode = OffscreenMode.NONE
	# Unified shield (shield_unification_2026-06-08.md): a no-regen CHARGE ShieldComponent
	# (carrying its own 24px ring) replaces the bespoke _shield/ring. Shield is up from
	# spawn; each hit spends one charge (Roman 2026-05-19 player-style 1-charge-1-hit).
	# Appended BEFORE super._ready() so _init_components dups it.
	var sh := ShieldComponent.new()
	sh.capacity = shield_health
	sh.regen_interval = 0.0
	sh.ring_size = 24.0
	# Reassign (not append) — @export Array defaults are shared across instances.
	components = components + [sh]
	super._ready()
	if has_node("Sprite2D"):
		# Skip the F0/F1 activation pageant and just sit on the shielded frame.
		$Sprite2D.hframes = 3
		$Sprite2D.frame = 2
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	position = pos
	_velocity = Vector2(0.0, drift_speed)

func _process(delta: float) -> void:
	if _dying:
		return
	position += _velocity * delta
	if position.y > screensize.y + 32.0:
		queue_free()

func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Free the ShieldComponent ring instantly so it doesn't linger over the explosion
	# (Roman, 2026-05-16: "shield should vanish first"). This explode() doesn't call
	# super.explode(), so fire the component death hook by hand.
	_components_death()
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
