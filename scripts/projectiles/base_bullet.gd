extends Area2D
class_name BaseBullet

# Shared bullet base for all gunfire — player + enemy + multi-hit + minigun.
# Refactored 2026-05-17 to consolidate the five-different-ways the bullet
# pipeline had drifted:
#   - off-screen kill bounds (each script had its own bounds)
#   - hit handling (bulwark-shielded check, hit-flash, take_hit fallback)
#   - damage routing (some used hardcoded 1, some used `damage`)
#   - target identification (some matched `area.name == "Player"` instead
#     of the player group)
#   - lifetime (no cap on most — relied on offscreen cleanup, would tick
#     forever if scene was paused or notifier failed)
#
# Subclasses override `_apply_visuals()` for sprite-specific glow/trail and
# `_on_hit_consumed(target)` if they want to drill through multiple
# targets (see bullet_wave.gd).
#
# Shape conventions:
#   target_group  — "enemies" for player bullets, "player" for enemy bullets
#   velocity_dir  — unit vector pointing where the bullet is heading
#   speed         — positive scalar in pixels/sec. Legacy scripts used a
#                   signed scalar with negative = upward; base_bullet
#                   normalizes by taking abs() and flipping the dir.

@export var target_group: String = "enemies"
@export var speed: float = 1400.0
@export var damage: int = 1
@export var velocity_dir: Vector2 = Vector2(0, -1)
@export var max_lifetime: float = 5.0
@export var guided: bool = false
# Impact effect kind (Roman, 2026-05-17 sprite pass). SMOKE for small
# energy/MG/laser bolts; EXPLOSIVE for missiles, rockets, cannon rounds,
# bomblets — see scripts/effects/impact_fx.gd::ImpactKind.
@export var impact_kind: int = 0  # 0=SMOKE, 1=EXPLOSIVE
# Color the impact picks up from. Subclasses override in _apply_visuals
# so the flash matches the bullet's muzzle / glow color.
@export var impact_color: Color = Color(1, 1, 1, 1)

var _t: float = 0.0
var _killed: bool = false

# 320×400 internal resolution (Roman, 2026-05-17 resolution rework).
const PLAYFIELD_MARGIN: float = 24.0
const PLAYFIELD_W: float = 320.0
const PLAYFIELD_H: float = 400.0


func _ready() -> void:
	# Legacy compat — some bullet .tscns ship with `speed = -1400` (negative
	# meaning "upward" in the old single-scalar API). Normalize: positive
	# speed + dir vector.
	if speed < 0.0:
		speed = abs(speed)
		velocity_dir = -velocity_dir
	if velocity_dir == Vector2.ZERO:
		velocity_dir = Vector2(0, -1)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_apply_visuals()


# Subclasses override to attach glow / trail. Base is a no-op so a plain
# bullet still moves+hits without any visual polish.
func _apply_visuals() -> void:
	pass


# Entry point — callers set position + optional direction. Backward-compat
# for the few callers that still pass just a position.
func start(pos: Vector2, dir: Vector2 = Vector2.ZERO) -> void:
	global_position = pos
	if dir != Vector2.ZERO:
		velocity_dir = dir.normalized()
	rotation = velocity_dir.angle() + PI * 0.5


func _process(delta: float) -> void:
	if _killed:
		return
	_t += delta
	global_position += velocity_dir * speed * delta
	if _t >= max_lifetime or _is_offscreen():
		queue_free()


func _is_offscreen() -> bool:
	var p: Vector2 = global_position
	return p.y < -PLAYFIELD_MARGIN \
		or p.y > PLAYFIELD_H + PLAYFIELD_MARGIN \
		or p.x < -PLAYFIELD_MARGIN \
		or p.x > PLAYFIELD_W + PLAYFIELD_MARGIN


# Unified hit pipeline. target_group determines who counts as a valid
# target; the damage routing differs (`take_hit` for enemies vs
# `take_damage` for the player).
func _on_area_entered(area: Area2D) -> void:
	if _killed or area == null:
		return
	if not area.is_in_group(target_group):
		return
	if target_group == "enemies":
		_apply_enemy_hit(area)
	else:
		_apply_player_hit(area)


func _apply_enemy_hit(area: Area2D) -> void:
	# Bulwark projection — enemies tagged via the BULWARK_SHIELDED meta
	# take no damage while their bulwark is alive. Bullet still fizzles
	# (the shield "ate" it) and a shield-tinted flash + hit sfx plays.
	if area.has_meta("bulwark_shielded"):
		var sprite_b = area.get_node_or_null("Sprite2D")
		if sprite_b is Sprite2D:
			var HitFlashFxB = load("res://scripts/effects/hit_flash_fx.gd")
			HitFlashFxB.flash(sprite_b, HitFlashFxB.FLASH_SHIELD)
		var ShieldSfxB = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfxB:
			ShieldSfxB.play_hit(get_tree().root, global_position)
		_finish_hit(area)
		return
	# Standard hit: white flash + unified take_hit damage call.
	var sprite = area.get_node_or_null("Sprite2D")
	if sprite is Sprite2D:
		var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
		HitFlashFx.flash(sprite, HitFlashFx.FLASH_WHITE)
	if area.has_method("take_hit"):
		area.take_hit(damage)
	else:
		# Legacy fallback for any enemy that hasn't migrated to EnemyBase.
		if "health" in area:
			area.health -= damage
			if area.health < 1:
				if area.has_method("explode"):
					area.explode()
			elif area.has_method("hit"):
				area.hit()
	_finish_hit(area)


func _apply_player_hit(area: Area2D) -> void:
	if area.has_method("take_damage"):
		area.take_damage(damage)
	_finish_hit(area)


# Default: one-shot. Override to drill through multiple enemies (e.g.
# bullet_wave's multi-hit behavior).
func _finish_hit(_target: Node) -> void:
	# Drop an impact effect at the hit position before the bullet frees.
	# Parented to the tree root so the effect outlives the bullet's
	# queue_free this frame.
	var ImpactFxCls = load("res://scripts/effects/impact_fx.gd")
	if ImpactFxCls:
		ImpactFxCls.spawn(get_tree().root, global_position, impact_color, impact_kind)
	_kill()


func _kill() -> void:
	if _killed:
		return
	_killed = true
	queue_free()


# Legacy notifier wiring — some .tscns have a VisibleOnScreenNotifier2D
# pre-connected to this signal. Keep the slot so the .tscn doesn't error.
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
