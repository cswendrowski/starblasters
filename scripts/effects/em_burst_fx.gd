extends Node

# EM Burst (Roman 2026-06-10) — the EM Torpedo's detonation. An electric-ball RING (the
# electric_ball.gdshader) blooms from the impact point and EXPANDS to the burst radius; the ring is
# what applies the effect — each enemy is zapped as the ring sweeps over it. Per enemy:
#   - Enemy ordnance (rockets/missiles) caught in the ring chain-detonates.
#   - Regular enemies: shields are stripped + ignored, the hull takes the burst damage, a crackling
#     on-sprite lightning overlay (electric_sprite.gdshader, masked to the silhouette) is applied,
#     and lethal hits are tagged "death_style"="disabled_em" so the kill routes to the disable death.
#
# Static entry: EmBurstFx.detonate(tree, world_pos, radius, damage, max_targets, fx_parent).

const _BALL_SHADER = preload("res://graphics/electric_ball.gdshader")
const _SPRITE_SHADER = preload("res://graphics/electric_sprite.gdshader")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

const BALL_TINT := Color(0.45, 0.72, 1.0, 1.0)   # electric blue-white; the shader tints by this
const QUAD_PX := 16.0                             # the ring quad's native size (scaled to 2*radius)

# Shared, lazily-built resources (the shaders animate off the global TIME, so one material each is
# fine; per-node modulate carries the per-instance colour/fade).
static var _noise_a: Texture2D = null
static var _noise_b: Texture2D = null
static var _white_tex: Texture2D = null
static var _sprite_mat: ShaderMaterial = null


# Build the noise/quad resources up front so the first detonation isn't dim while NoiseTexture2D
# generates on its thread. Safe to call repeatedly (idempotent). Call on combat / test start.
static func prewarm() -> void:
	_ensure_resources()


static func _ensure_resources() -> void:
	if _noise_a == null:
		_noise_a = _make_noise(1337)
	if _noise_b == null:
		_noise_b = _make_noise(9001)
	if _white_tex == null:
		var img := Image.create(int(QUAD_PX), int(QUAD_PX), false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_white_tex = ImageTexture.create_from_image(img)
	if _sprite_mat == null:
		_sprite_mat = ShaderMaterial.new()
		_sprite_mat.shader = _SPRITE_SHADER
		_sprite_mat.set_shader_parameter("noise", _noise_a)
		_sprite_mat.set_shader_parameter("noise2", _noise_b)


static func _make_noise(seed_i: int) -> Texture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	nt.as_normal_map = false
	var fn := FastNoiseLite.new()
	fn.seed = seed_i
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	fn.frequency = 0.03
	nt.noise = fn
	return nt


static func _make_ball_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _BALL_SHADER
	mat.set_shader_parameter("noise", _noise_a)
	mat.set_shader_parameter("noise2", _noise_b)
	mat.set_shader_parameter("brightness", 2.5)
	mat.set_shader_parameter("time_scale", 1.4)
	return mat


# Spawn the expanding electric ring at the detonation point. `fx_parent` is the torpedo's fx
# container (the combat scene), so the ring shares world coordinates with the enemies.
static func detonate(tree: SceneTree, world_pos: Vector2, radius: float, damage: int, max_targets: int, fx_parent: Node) -> void:
	if tree == null:
		return
	_ensure_resources()
	var parent: Node = fx_parent if (fx_parent != null and is_instance_valid(fx_parent)) else BulletWorld.spawn_root(tree, tree.current_scene if tree.current_scene != null else tree.root)
	var ring := EmBurstRing.new()
	ring.setup(world_pos, radius, damage, max_targets, _white_tex, _make_ball_material(), _sprite_mat, BALL_TINT)
	parent.add_child(ring)


# ----------------------------------------------------------------------------------------------
# The expanding electric-ball ring. Grows from 0 to the burst radius, zapping each enemy as the ring
# sweeps over it (the ring IS the AoE), then holds + fades and frees itself. Self-contained (it's
# handed the shared materials, so it never reaches back into the outer script).
class EmBurstRing extends Node2D:
	var _center: Vector2
	var _max_r: float = 72.0
	var _damage: int = 6
	var _max_targets: int = 8
	var _applied: int = 0
	var _t: float = 0.0
	var _hit: Dictionary = {}
	var _ball: Sprite2D = null
	var _sprite_mat: ShaderMaterial = null
	var _quad_px: float = 16.0
	const EXPAND_TIME := 0.26
	const HOLD_TIME := 0.06
	const FADE_TIME := 0.22

	func setup(center: Vector2, radius: float, damage: int, max_targets: int, white_tex: Texture2D, ball_mat: ShaderMaterial, sprite_mat: ShaderMaterial, tint: Color) -> void:
		_center = center
		_max_r = maxf(radius, 1.0)
		_damage = damage
		_max_targets = max_targets
		_sprite_mat = sprite_mat
		global_position = center
		z_index = 4
		_ball = Sprite2D.new()
		_ball.texture = white_tex
		_quad_px = float(white_tex.get_width()) if white_tex != null else 16.0
		_ball.centered = true
		_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ball.modulate = tint
		_ball.material = ball_mat
		add_child(_ball)
		_ball.scale = Vector2.ONE * (2.0 / _quad_px)   # start tiny

	func _process(delta: float) -> void:
		_t += delta
		var expand: float = clampf(_t / EXPAND_TIME, 0.0, 1.0)
		var cur_r: float = _max_r * smoothstep(0.0, 1.0, expand)
		if _ball != null and is_instance_valid(_ball):
			_ball.scale = Vector2.ONE * (2.0 * maxf(cur_r, 1.0) / _quad_px)
		# The ring sweeps outward — zap enemies as it reaches them (nearest first, by construction).
		if _applied < _max_targets:
			_zap_within(cur_r)
		# Hold at full, then fade out.
		if _t >= EXPAND_TIME + HOLD_TIME:
			var fade_t: float = (_t - EXPAND_TIME - HOLD_TIME) / FADE_TIME
			if _ball != null and is_instance_valid(_ball):
				_ball.modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)
			if fade_t >= 1.0:
				queue_free()

	func _zap_within(r: float) -> void:
		var tree := get_tree()
		if tree == null:
			return
		for e in tree.get_nodes_in_group("enemies"):
			if _applied >= _max_targets:
				return
			if not is_instance_valid(e) or not (e is Node2D):
				continue
			var id: int = e.get_instance_id()
			if _hit.has(id):
				continue
			if (e as Node2D).global_position.distance_to(_center) > r:
				continue
			_hit[id] = true
			_applied += 1
			_zap_enemy(e)

	# Apply the EM effect to one enemy: chain-detonate ordnance, else strip shields, crackle the
	# hull, tag a lethal hit for the disable death, and deal the (shield-ignoring) damage.
	func _zap_enemy(e: Node) -> void:
		if not is_instance_valid(e):
			return
		# Enemy ordnance (target_group=="player", in the "enemies" group) detonates. Our own torpedo
		# is target_group=="enemies" and NOT in the group, so it's never caught here.
		if "target_group" in e and String(e.get("target_group")) == "player" and e.has_method("explode"):
			e.explode()
			return
		if e.has_method("break_shields"):
			e.break_shields()
		if "health" in e and int(e.get("health")) <= _damage and e.has_method("set_meta"):
			e.set_meta("death_style", "disabled_em")
		_apply_sprite_lightning(e)   # before take_hit so it rides along even if this kills the enemy
		if e.has_method("take_hit"):
			e.take_hit(_damage)

	# Crackling on-sprite lightning: an additive overlay that copies the enemy's current frame (so the
	# shader masks the crackle to the hull silhouette), fading out over ~0.45s.
	func _apply_sprite_lightning(e: Node) -> void:
		var spr: Node = e.get_node_or_null("Sprite2D")
		if spr == null or not (spr is Sprite2D) or _sprite_mat == null:
			return
		var s: Sprite2D = spr
		var ov := Sprite2D.new()
		ov.texture = s.texture
		ov.hframes = s.hframes
		ov.vframes = s.vframes
		ov.frame = s.frame
		ov.centered = s.centered
		ov.offset = s.offset
		ov.flip_h = s.flip_h
		ov.flip_v = s.flip_v
		ov.region_enabled = s.region_enabled
		ov.region_rect = s.region_rect
		ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ov.z_index = 1   # above the hull, additive
		ov.material = _sprite_mat
		s.add_child(ov)
		var tw := ov.create_tween()
		tw.tween_property(ov, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(ov.queue_free)
