extends "res://scripts/enemies/enemy_base.gd"

# Firecore lane hazard (M6b §8) — the Evantian Theocracy (zealot) faction's signature
# drop. A zealot enemy's DropFirecore Emitter spawns one of these at its lane position
# on death (by chance). A small, pulsing yellow ember that drifts slowly down its lane,
# explodes on contact with the player, and is destructible (shoot it to clear it).
#
# Modeled on mine.gd: is_hazard = true (doesn't gate level-clear, rides hazard pacing),
# explodes on player contact, takes bullet damage normally. Lane-anchored = holds its
# spawn X; the slow downward drift lets it clear the band (off-bottom despawn) with a
# lifetime fallback so a low-spawned ember never lingers.

# Firecore embers share the "engines" HDR-glow multiplier (Roman 2026-06-22) so the WorldEnvironment
# blooms them. VfxGlow is inherited from enemy_base.

@export var drift_speed: float = 45.0        # slow lane drift (mines are 120)
@export var damage_on_collide: int = 2
@export var lifetime: float = 7.0            # safety despawn if it never clears the band

var _t: float = 0.0


func _ready() -> void:
	max_health = 2          # destructible
	is_hazard = true        # hazard: no level-clear gate, hazard pacing
	bounty_value = 1
	display_scale = 1.0
	auto_rotate = false     # an ember has no "forward"
	has_ship_vfx = false    # no ground shadow / damage-overlay — it explodes, not frays
	wants_outline = false  # firecores are excepted from the hull outline
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	var spr := _sprite()
	if spr != null:
		if spr is AnimatedSprite2D:
			(spr as AnimatedSprite2D).play("default")
		# HDR modulate → the WorldEnvironment bloom glows the ember (uses the tuned "engines"
		# multiplier). The engine trail comes from the Engine marker.
		spr.modulate = VfxGlow.prod_hdr("engines")


func _sprite() -> CanvasItem:
	if has_node("AnimatedSprite2D"):
		return get_node("AnimatedSprite2D")
	if has_node("Sprite2D"):
		return get_node("Sprite2D")
	return null


func start(pos: Vector2) -> void:
	position = pos
	_t = 0.0


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	position.y += drift_speed * delta
	if position.y > screensize.y + 16.0 or _t >= lifetime:
		queue_free()


# Bullet hit — flash only; EnemyBase.take_hit routes lethal hits through explode().
func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()


# Firecore death VFX — explosion + mine sfx, then free (mine.gd-style override).
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# Explicit type — `:=` can't infer from an untyped load() result, and the inference failure
	# kills the WHOLE script at runtime (frozen, unkillable firecores; Roman 2026-06-10).
	var scene: PackedScene = ExplosionFx.scene_for("ball")
	ExplosionFx.play(global_position, 1.0, true, null, scene)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	await get_tree().create_timer(0.4).timeout
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
