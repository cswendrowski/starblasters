extends Area2D
class_name BaseBullet

# Shared bullet base for all gunfire — player + enemy + multi-hit + minigun.
# Variant system: assign a BulletVariant resource before start() to override
# speed, damage, lifetime, hitbox, visuals, glow color, and behavior knobs
# (wobble, homing, telegraph_flash, random_frame). variant == null = unchanged
# behavior so all existing bullets work without modification.
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

@export var variant: BulletVariant = null
@export var target_group: String = "enemies"
@export var speed: float = 1400.0
@export var damage: int = 1
@export var velocity_dir: Vector2 = Vector2(0, -1)
@export var max_lifetime: float = 5.0
@export var guided: bool = false
# Projectile-movement axis (M6a.2). These are the bullet's OWN movement knobs,
# seeded from the variant in _apply_variant() (so variant-authored movement is
# unchanged) but settable by the firing layer (a Weapon) AFTER spawn to drive
# homing/wobble independent of the variant's visuals. _process reads these, not the
# variant — so faction/weapon multipliers and the boss tracker/plasma restore route
# through here. homing_rate = deg/s turn toward the target group; wobble = perpendicular
# sine (amplitude px, frequency Hz).
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0
# Impact effect kind (Roman, 2026-05-17 sprite pass). SMOKE for small
# energy/MG/laser bolts; EXPLOSIVE for missiles, rockets, cannon rounds,
# bomblets — see scripts/effects/impact_fx.gd::ImpactKind.
@export var impact_kind: int = 0  # 0=SMOKE, 1=EXPLOSIVE
# Color the impact picks up from. Subclasses override in _apply_visuals
# so the flash matches the bullet's muzzle / glow color.
@export var impact_color: Color = Color(1, 1, 1, 1)

var _t: float = 0.0
var _killed: bool = false
# Wobble support: we advance the canonical position without wobble offset
# so the offset is purely re-derived each frame (no drift accumulation).
var _base_position: Vector2 = Vector2.ZERO
var _wobble_active: bool = false

# 480×270 internal resolution (horizontal rework 2026-05-19).
const PLAYFIELD_MARGIN: float = 24.0
const PLAYFIELD_W: float = 480.0
const PLAYFIELD_H: float = 270.0


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
	# Seed _base_position from current position so bullets that skip start()
	# don't teleport to (0,0) on first frame.
	_base_position = global_position
	# Apply variant data before _apply_visuals() so subclass overrides can
	# read variant-set values and gate their own logic.
	if variant != null:
		_apply_variant()
	_apply_visuals()
	_apply_hdr_bloom()


# Subclasses override to attach glow / trail. Base is a no-op so a plain
# bullet still moves+hits without any visual polish.
func _apply_visuals() -> void:
	pass


# Push the bolt sprite into the HDR range so the combat WorldEnvironment bloom (glow_hdr_threshold
# = 1.0 in main.tscn) glows it directly — replaces the removed per-bullet glow-halo quad (Roman
# 2026-06-12). Only the bright bolt pixels exceed 1.0, so transparent edges stay matte: no
# rectangular halo, no frame-bleed ghost. Gain is one-line tunable. Subclasses with a nested core
# (swarm_missile) brighten it themselves.
const BULLET_HDR_GAIN := 1.8

func _apply_hdr_bloom() -> void:
	for nm in ["Sprite2D", "AnimatedSprite2D", "BulletSprite", "Core"]:
		var n := get_node_or_null(nm)
		if n is CanvasItem:
			var ci := n as CanvasItem
			var c := ci.self_modulate
			ci.self_modulate = Color(c.r * BULLET_HDR_GAIN, c.g * BULLET_HDR_GAIN, c.b * BULLET_HDR_GAIN, c.a)


# Apply a BulletVariant's stat and visual overrides. Called from _ready()
# when variant != null. Subclasses should gate their own _apply_visuals
# glow on `variant == null` so the variant glow_color wins.
func _apply_variant() -> void:
	speed = variant.speed
	damage = variant.damage
	max_lifetime = variant.lifetime
	impact_kind = variant.impact_kind
	impact_color = variant.impact_color

	# --- hitbox ---
	# The per-bullet SCENE owns its collision shape now (Roman 2026-06-08: "I've updated the
	# projectile scenes with correct hitboxes"). The variant no longer overrides it — every
	# indexed bullet scene carries its own authored hitbox, so forcing variant.hitbox_size
	# here just clobbered the scene value (e.g. the cannon's 6x16 -> 5x5). hitbox_size stays
	# on BulletVariant for reference/data but is not applied.

	# --- visuals ---
	if variant.sprite_frames != null:
		# Animated bullet: hide the static Sprite2D (if any), use AnimatedSprite2D.
		var asp: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if asp != null:
			asp.sprite_frames = variant.sprite_frames
			if variant.random_frame:
				var fc: int = variant.sprite_frames.get_frame_count("default")
				asp.frame = randi() % fc if fc > 0 else 0
				asp.stop()
			else:
				asp.play("default")
	elif variant.static_texture != null and variant.frame_count > 1:
		# Animated strip: build (or reuse cached) SpriteFrames from the PNG
		# strip and drive the scene's AnimatedSprite2D.
		var asp: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if asp != null:
			# Build SpriteFrames once per variant and cache on the resource to
			# avoid per-bullet allocation in bullet-heavy scenarios.
			if variant._built_frames == null:
				var tex: Texture2D = variant.static_texture
				var frame_w: int = tex.get_width() / variant.frame_count
				var frame_h: int = tex.get_height()
				var frames := SpriteFrames.new()
				frames.set_animation_loop("default", true)
				frames.set_animation_speed("default", variant.fps)
				for i in range(variant.frame_count):
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
					frames.add_frame("default", atlas)
				variant._built_frames = frames
			asp.sprite_frames = variant._built_frames
			if variant.random_frame:
				asp.frame = randi() % variant.frame_count
				asp.stop()
			else:
				asp.play("default")
			asp.visible = true
	elif variant.static_texture != null:
		# Single-frame static texture: hide AnimatedSprite2D, set Sprite2D.
		var asp: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if asp != null:
			asp.visible = false
		var sp: Sprite2D = _get_bullet_sprite()
		if sp != null:
			sp.texture = variant.static_texture
			sp.visible = true
			if variant.random_frame:
				# Static texture with frame picking: nothing to randomize,
				# but support is harmless.
				pass

	# --- glow color ---
	# The shader halo (glow_shader_fx) reads variant.glow_color in the
	# subclass _apply_visuals; nothing to do here. The old scene "Glow"
	# child has been removed from all projectile scenes.

	# --- telegraph flash ---
	if variant.telegraph_flash:
		_do_telegraph_flash()

	# --- movement axis (seed from variant; the firing layer may override post-spawn) ---
	homing_rate = variant.homing_rate
	wobble_amplitude = variant.wobble_amplitude
	wobble_frequency = variant.wobble_frequency
	if wobble_amplitude > 0.0:
		_wobble_active = true


# Return the bullet's own Sprite2D (NOT the shader-glow halo). Creates a
# child named "BulletSprite" if none exists.
func _get_bullet_sprite() -> Sprite2D:
	# First look for an existing bullet Sprite2D child (skip the glow halo).
	for child in get_children():
		if child is Sprite2D and child.name != "ShaderGlow":
			return child as Sprite2D
	# Create one if missing.
	var s := Sprite2D.new()
	s.name = "BulletSprite"
	add_child(s)
	return s


# Brief white flash on the AnimatedSprite2D to telegraph an incoming heavy
# shot. Tween modulate white → original color over ~0.15 s.
func _do_telegraph_flash() -> void:
	var asp: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var target: CanvasItem = asp if asp != null else self
	target.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color(1, 1, 1, 1), 0.0)
	tw.tween_property(target, "modulate", Color(1, 1, 1, 0.3), 0.08)
	tw.tween_property(target, "modulate", Color(1, 1, 1, 1), 0.07)


# Entry point — callers set position + optional direction. Backward-compat
# for the few callers that still pass just a position.
func start(pos: Vector2, dir: Vector2 = Vector2.ZERO) -> void:
	global_position = pos
	if dir != Vector2.ZERO:
		velocity_dir = dir.normalized()
	rotation = velocity_dir.angle() + PI * 0.5
	_base_position = pos


func _process(delta: float) -> void:
	if _killed:
		return
	_t += delta

	# Homing: steer velocity_dir toward the nearest node in target_group at
	# homing_rate deg/s. Target-group-aware (enemy bullets home the player; player
	# bullets could home enemies) — reads the bullet's own homing_rate (set from the
	# variant, or overridden by the firing layer).
	if homing_rate > 0.0:
		var target: Node2D = _homing_target()
		if target != null:
			var to_t: Vector2 = target.global_position - global_position
			if to_t.length_squared() > 0.0001:
				var target_dir: Vector2 = to_t.normalized()
				var max_turn: float = deg_to_rad(homing_rate) * delta
				velocity_dir = velocity_dir.rotated(
					clampf(velocity_dir.angle_to(target_dir), -max_turn, max_turn)
				)
				rotation = velocity_dir.angle() + PI * 0.5

	# Advance canonical (non-wobble) position.
	_base_position += velocity_dir * speed * delta

	# Wobble: offset perpendicular to velocity_dir, re-derived each frame.
	if wobble_amplitude > 0.0:
		var perp: Vector2 = Vector2(-velocity_dir.y, velocity_dir.x)
		var offset: float = sin(_t * wobble_frequency * TAU) * wobble_amplitude
		global_position = _base_position + perp * offset
	else:
		global_position = _base_position

	if _t >= max_lifetime or _is_offscreen():
		queue_free()


# Nearest live node in target_group (homing only — runs per-frame for homing
# bullets, which are rare). For enemy bullets (target_group "player") this is the
# single player; for player bullets ("enemies") it's the nearest enemy.
func _homing_target() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for n in tree.get_nodes_in_group(target_group):
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = (n as Node2D).global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


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
			ShieldSfxB.play_hit(_fx_parent(), global_position)
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
# The container a hit effect should spawn into: this bullet's own parent, so it
# shares the bullet's coordinate space and outlives its queue_free. In combat
# that's the window root (bullets parent there); in the hangar SubViewport
# preview it's `_world`. Falls back to root if somehow unparented.
func _fx_parent() -> Node:
	var p: Node = get_parent()
	return p if (p != null and is_instance_valid(p)) else get_tree().root


func _finish_hit(_target: Node) -> void:
	# Drop an impact effect at the hit position before the bullet frees, parented
	# to the bullet's own container so it outlives the queue_free this frame AND
	# renders in the right space (window-root in combat, SubViewport in hangar).
	var ImpactFxCls = load("res://scripts/effects/impact_fx.gd")
	if ImpactFxCls:
		ImpactFxCls.spawn(_fx_parent(), global_position, impact_color, impact_kind)
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
