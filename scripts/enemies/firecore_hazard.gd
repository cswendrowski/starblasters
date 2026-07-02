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
# Lateral drift mode (Roman 2026-06-23). Default "straight" = the historical lane-anchored ember
# (no sideways motion); the conductor can set "drift_lane"/"drift_adjacent"/"drift_all" to make
# embers wander. Reuses the shared LateralDrift pattern (same as the asteroid).
@export var drift_mode: String = "straight"
const LateralDrift = preload("res://scripts/enemies/patterns/lateral_drift.gd")
var _drift: Resource = null

# Optional initial SCATTER impulse (Roman 2026-07-01) — set before start() to fling the ember outward
# (e.g. the battleship's firecore release fans them out); it decays over ~0.5s, after which the normal
# lane drift carries on. Default zero = the historical straight drop (faction drop unchanged).
@export var burst_velocity: Vector2 = Vector2.ZERO
const BURST_DECAY: float = 3.0   # per-second exponential-ish decay of the scatter impulse
var _burst: Vector2 = Vector2.ZERO

# Optional initial SCALE (Roman 2026-07-01) — set <1 before start() so the ember starts small and GROWS
# to full size, reading as "rising into the foreground" from a distant (background) source (the
# battleship's background firecore hook). Default 1.0 = spawns full-size (faction drop / slide unchanged).
@export var spawn_scale: float = 1.0
const GROW_DURATION: float = 0.5   # matches ~the burst decay, so it's full-size by the time it settles

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
	# Descent intake (speed-source pass): a handed move_speed (bench/director) drives the drop;
	# otherwise the authored drift_speed holds. Never overrides a handed value.
	if move_speed > 0.0:
		drift_speed = move_speed
	super._ready()
	_drift = LateralDrift.new()
	_drift.mode = LateralDrift.mode_from_key(drift_mode)
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
	_burst = burst_velocity   # initial scatter impulse (decays into the normal drift)
	# Grow from a small "distant" size to full as it rises into the foreground (background hook release).
	if spawn_scale < 0.999:
		scale = Vector2(spawn_scale, spawn_scale)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, GROW_DURATION).set_trans(Tween.TRANS_SINE)
	if _drift != null:
		_drift.on_start(self)   # capture the home lane for the confined modes


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	# Decaying scatter impulse (fan-out on release), then the normal lane drift takes over.
	if _burst.length_squared() > 1.0:
		position += _burst * delta
		_burst = _burst.lerp(Vector2.ZERO, clampf(BURST_DECAY * delta, 0.0, 1.0))
	if _drift != null:
		position.x += _drift.compute_step(self, delta).x   # lateral wander (STRAIGHT = no-op)
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


# Brief arm delay after spawn so a just-released ember (e.g. the battleship scattering its cores as it
# dives) doesn't instantly detonate on a player it spawned near — it scatters + drifts first.
const ARM_DELAY: float = 0.3


func _on_area_entered(area: Area2D) -> void:
	if _t < ARM_DELAY:
		return
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
