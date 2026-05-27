extends Area2D
class_name EnemyBase

# Debris strip used on death (Roman 2026-05-18).
const DEBRIS_STRIP_TEX = preload("res://graphics/effects/debris.png")
const DEBRIS_FRAME_COUNT: int = 6
const DEBRIS_LIFETIME: float = 1.6
const DEBRIS_DRIFT_BASE: float = 225.0
const DEBRIS_DRIFT_GAIN: float = 400.0
const DEBRIS_BURST_MIN: float = 140.0
const DEBRIS_BURST_MAX: float = 280.0
# Fixed sprite scale regardless of enemy size — only count scales with
# enemy (Roman 2026-05-18).
const DEBRIS_PIECE_SCALE: float = 1.0   # native size (Roman 2026-05-19)
const DEBRIS_SPIN_MIN: float = -8.0
const DEBRIS_SPIN_MAX: float = 8.0

# Module-level preloads — every enemy _ready + every enemy explode used
# to do `load(...)` and re-parse these scripts. Hoisted to const so the
# parse + class lookup happens once per project load.
const EnemyEngineFxScript = preload("res://scripts/effects/enemy_engine_fx.gd")
const ParallaxShadowScript = preload("res://scripts/effects/parallax_shadow.gd")
const DamageOverlayShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoiseTex = preload("res://resources/noise_damage.tres")
const _DamageEdgeTex = preload("res://resources/edge_distance_flat.tres")
const ExplosionFxScript = preload("res://scripts/effects/explosion_fx.gd")
const DeathDustScript = preload("res://scripts/effects/death_dust.gd")
const BurnFxScript = preload("res://scripts/burn_fx.gd")
const SHIELD_SHADER = preload("res://graphics/sci_fi_shield.gdshader")

# Shared base for everything that joins the "enemies" group — regular
# pattern-driven ships (via enemy_core), hazards (mines, asteroids,
# bomblets), and projectile-as-enemy types (drifting missiles). Replaces
# the three-island arrangement where each script reimplemented `health`,
# `hit()`, `explode()`, `died`, and `_find_player()` from scratch.
#
# Contract for bullets (player + future weapons):
#   area.take_hit(damage) → returns true if the hit killed the enemy
# bullet.gd has a fallback for the legacy `area.health -= 1 ; area.explode()`
# path so any enemy that hasn't migrated yet still works.
#
# Off-screen behavior is declared via `offscreen_mode`:
#   CYCLE_BOTTOM       — only the bottom exit triggers cleanup. enemy_core
#                        overrides _on_offscreen() to do its parallax-cycle
#                        fly-back instead of freeing.
#   FREE_ANY_EDGE      — exit on any edge frees the enemy. Kamikazes
#                        (Hunter Drone) and small projectiles use this.
#   FREE_OPPOSITE_SIDE — once the enemy has crossed past the playfield
#                        sideways it queue_frees. Side-traversing leavers
#                        like the Minelayer.
#   NONE               — no automatic offscreen handling. Caller is
#                        responsible (rare; bosses are NONE because they
#                        live inside the playfield).

signal died(value)

enum OffscreenMode { CYCLE_BOTTOM, FREE_ANY_EDGE, FREE_OPPOSITE_SIDE, NONE }

@export var max_health: int = 1
@export var bounty_value: int = 5
@export var max_shield: int = 0
@export var shield_ring_size: float = 28.0
# Hazards (mines, bomblets, asteroids) should not gate wave clear —
# they're terrain, not combatants (Cody, 2026-05-18). Wave director
# filters the "enemies" group by this flag when checking for empty.
@export var is_hazard: bool = false
@export var display_scale: float = 1.0
@export var offscreen_mode: int = OffscreenMode.CYCLE_BOTTOM
# Engine flame color override. Default warm-orange; missile-like enemies
# (Dart) use yellow per Roman 2026-05-18. Alpha is honored.
@export var engine_tint: Color = Color(1.0, 0.65, 0.25, 0.95)
@export var engine_scale_mult: float = 1.0
# Margin past the visible edge at which FREE_* modes activate. Wide enough
# that on-screen wobble never trips us, narrow enough that escaped enemies
# clear the wave promptly.
@export var offscreen_margin: float = 32.0  # 320×400 res rework
# Auto-rotate the sprite to face the velocity direction. Pattern-driven
# ships (combat enemies) enable this so a turning enemy actually banks.
# Mines, bomblets, asteroids set this to false in their _ready — they
# don't have a "front" in the same sense.
@export var auto_rotate: bool = true
# Allow this enemy to leave through the screen sides without being
# clamped back into the playfield. Patterns (side_traverse, side_cut,
# advance_retreat, top_dive) set this to true. Declared on the base so
# the dynamic-assignment in patterns lands on a real property.
var allow_side_exit: bool = false

var health: int = 1
var shield: int = 0
var recycle_passes: int = -1   # -1 = unlimited (matches current default behavior)
var damage_reduction: float = 0.0  # 0.0–1.0; set by sector modifiers (armored/heavily_armored)
var _dying: bool = false
var _last_position: Vector2 = Vector2.ZERO
var _rot_init: bool = false

# Cached viewport size — used by subclasses for off-screen checks and side
# clamps. Set in _ready() (not @onready) so subclasses can use it from their
# own _ready() without ordering concerns.
var screensize: Vector2 = Vector2(800, 1000)


func _ready() -> void:
	screensize = get_viewport_rect().size
	health = max_health
	shield = max_shield
	# Allow rapid $EnemyShoot.play() calls to overlap so each shot is
	# audible to completion (Roman feedback 2026-05-23). $EnemyDie is
	# handled separately in explode() via Sfx.play_node_detached.
	var SfxCls = load("res://scripts/effects/sfx.gd")
	if has_node("EnemyShoot"):
		SfxCls.ensure_polyphony($EnemyShoot, 4)
	if max_shield > 0:
		_setup_shield_ring()
	# Defensive group registration. Every enemy .tscn already declares
	# `groups=["enemies"]` on its root; this is the safety net for any
	# enemy that was instantiated from script without a scene.
	if not is_in_group("enemies"):
		add_to_group("enemies")
	# Legacy enemy .tscns use Sprite2D.flip_v = true to point art "down" at
	# the player. With auto-rotation now driving direction, the flip causes
	# sprites to render backward (sprite is flipped, then rotated 180° to
	# face down → ends up facing up while travelling down). Clear flip_v
	# so auto_rotate is authoritative. Roman, 2026-05-16: "all enemies
	# are flying backward except the ones whose sprites weren't flipped".
	if auto_rotate and has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		if spr and spr.flip_v:
			spr.flip_v = false
	# Engine flame trail. Same gate as auto_rotate — ships need it,
	# mines/asteroids/bomblets don't.
	if auto_rotate:
		EnemyEngineFxScript.attach(self, engine_tint, engine_scale_mult)
		# Ground-shadow on the top parallax layer. Same gate (ships only).
		ParallaxShadowScript.attach(self)
	# Damage overlay shader (Roman, 2026-05-18): darken + fray the sprite
	# as health drops. Only applied to ships (auto_rotate gate) — mines,
	# asteroids, bomblets explode on death rather than scaling damage.
	if auto_rotate and has_node("Sprite2D"):
		_install_damage_material($Sprite2D)


var _damage_material: ShaderMaterial = null
var _shield_ring: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_alpha_tween: Tween = null
var _shield_hit_tween: Tween = null


func _install_damage_material(spr: Sprite2D) -> void:
	if spr == null or spr.material != null:
		return  # don't stomp a pre-existing material (hologram, etc.)
	var mat := ShaderMaterial.new()
	mat.shader = DamageOverlayShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
	mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	spr.material = mat
	_damage_material = mat


func _update_damage_visual() -> void:
	if _damage_material == null:
		return
	if max_health <= 0:
		return
	# 0 at full health → 1 at zero health. Capped slightly under 1 so the
	# sprite still reads on the frame before explode() fires.
	var lvl: float = clamp(1.0 - float(health) / float(max_health), 0.0, 0.92)
	_damage_material.set_shader_parameter("sensitivity", lvl)


# ---- Bullet hit pipeline -----------------------------------------------

# Single damage entry point. Returns true if the hit was fatal so callers
# can act on it (e.g. award bounty, spawn pickup) without parsing the
# death signal.
func take_hit(damage: int = 1) -> bool:
	if _dying:
		return false
	if shield > 0:
		shield -= 1
		_pulse_shield_hit()
		var HitFlashFxShield = load("res://scripts/effects/hit_flash_fx.gd")
		if has_node("Sprite2D"):
			HitFlashFxShield.flash($Sprite2D, HitFlashFxShield.FLASH_SHIELD)
		var ShieldSfx2 = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfx2:
			if shield <= 0:
				ShieldSfx2.play_break(get_tree().root, global_position)
				_set_shield_alpha(0.0, 0.25)
			else:
				ShieldSfx2.play_hit(get_tree().root, global_position)
		return false
	var effective_dmg: int = max(1, int(round(float(damage) * (1.0 - damage_reduction))))
	health -= effective_dmg
	# Push the new health ratio into the damage shader so the sprite
	# darkens + frays as it takes damage (Roman, 2026-05-18).
	_update_damage_visual()
	if health < 1:
		explode()
		return true
	hit()
	return false


# Non-fatal hit reaction. Overridable; default plays the ParticleHit node
# if the scene has one.
func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()


# Death pipeline. Overridable but the default covers the common case:
# fire `died(bounty_value)`, drop monitorable, play explosion VFX + burn,
# wait a beat, queue_free.
func explode() -> void:
	if _dying:
		return
	if _shield_ring and is_instance_valid(_shield_ring):
		_shield_ring.visible = false
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Explosions are always 1× scale; bigger enemies just get MORE blasts
	# with random jitter (Roman 2026-05-18). 16-px chaff = 1, 48-px boss-
	# class = ~4-5, clamped to a sane upper bound.
	var blast_count: int = clampi(int(round(max(1.0, display_scale * 1.4))), 1, 6)
	if blast_count <= 1:
		ExplosionFxScript.play(global_position, 1.0)
	else:
		ExplosionFxScript.burst(global_position, blast_count, 12.0 * max(1.0, display_scale * 0.6), 0.06)
	# Settling dust supplement (Roman 2026-05-24): 1px gray particles
	# scattering radially with downward gravity. Count scales with size
	# (8/16/32/64). Fires alongside the debris strip, not instead of it.
	# For boss-class enemies (display_scale large enough to trigger the
	# multi-blast cascade above) the bigger count bucket gives each blast
	# a corresponding dust puff feel without per-blast wiring.
	DeathDustScript.play(global_position, display_scale)
	# Debris scatter (Roman 2026-05-18). Parent under scene root so the
	# pieces survive the enemy's queue_free at the end of explode().
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	_spawn_debris(parent, global_position, display_scale)
	if has_node("Sprite2D"):
		BurnFxScript.apply_burn($Sprite2D, 0.45)
	if has_node("ParticleExplode"):
		$ParticleExplode.restart()
	if has_node("EnemyDie"):
		# Detach the death SFX from the dying enemy so it plays to
		# completion instead of clipping when queue_free() fires below
		# (Roman feedback 2026-05-23). Sfx.play_node_detached re-parents
		# under root.
		var SfxCls = load("res://scripts/effects/sfx.gd")
		SfxCls.play_node_detached($EnemyDie)
	await get_tree().create_timer(0.5).timeout
	queue_free()


func _spawn_debris(parent: Node, world_pos: Vector2, scale_factor: float) -> void:
	# Piece count scaled by enemy size. 16-px chaff → ~3 pieces, 48-px
	# elite → ~9. Clamped.
	var count: int = clampi(int(round(2.0 + scale_factor * 2.3)), 2, 12)
	for i in count:
		_spawn_debris_piece(parent, world_pos, scale_factor)


func _spawn_debris_piece(parent: Node, world_pos: Vector2, scale_factor: float) -> void:
	var s := Sprite2D.new()
	s.texture = DEBRIS_STRIP_TEX
	s.hframes = DEBRIS_FRAME_COUNT
	s.vframes = 1
	s.frame = randi() % DEBRIS_FRAME_COUNT
	s.scale = Vector2.ONE * DEBRIS_PIECE_SCALE
	s.global_position = world_pos
	s.rotation = randf_range(0.0, TAU)
	s.z_index = 6
	s.z_as_relative = false
	parent.add_child(s)
	var spin: float = randf_range(DEBRIS_SPIN_MIN, DEBRIS_SPIN_MAX)
	# Burst direction biased to the LOWER hemisphere (Roman 2026-05-18):
	# the enemy was already moving down when it died, so debris should
	# scatter outward AND immediately start heading down — no "frozen in
	# place then falls" beat. 0=right, PI/2=down, PI=left. Tiny clamp off
	# the horizontal so a piece doesn't go perfectly sideways.
	var burst_angle: float = randf_range(0.10, PI - 0.10)
	var burst_speed: float = randf_range(DEBRIS_BURST_MIN, DEBRIS_BURST_MAX)
	var burst_vel: Vector2 = Vector2(cos(burst_angle), sin(burst_angle)) * burst_speed
	# X (lateral scatter): pops out fast then plateaus.
	# Y (downward): accelerates over the full lifetime — burst contributes
	# the initial Y, drift compounds it. TRANS_QUAD ease_in mimics gravity.
	var burst_dx: float = burst_vel.x * (DEBRIS_LIFETIME * 0.35)
	var burst_dy: float = burst_vel.y * (DEBRIS_LIFETIME * 0.5)
	var drift_dy: float = DEBRIS_DRIFT_BASE * DEBRIS_LIFETIME + 0.5 * DEBRIS_DRIFT_GAIN * DEBRIS_LIFETIME
	var end_x: float = world_pos.x + burst_dx
	var end_y: float = world_pos.y + burst_dy + drift_dy
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "rotation", s.rotation + spin * DEBRIS_LIFETIME, DEBRIS_LIFETIME)
	tw.tween_property(s, "global_position:x", end_x, DEBRIS_LIFETIME)\
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "global_position:y", end_y, DEBRIS_LIFETIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(s, "modulate:a", 0.0, DEBRIS_LIFETIME * 0.3).set_delay(DEBRIS_LIFETIME * 0.7)
	tw.set_parallel(false)
	tw.tween_callback(s.queue_free)


# ---- Shared helpers ----------------------------------------------------

# Cheap player lookup. Returns null if the player isn't in the scene tree
# yet (very early in level start) or has been freed (post-death).
func find_player() -> Node:
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null


# Per-frame offscreen check + optional sprite auto-rotation. Subclasses
# should call this from their _process() AFTER moving themselves, OR
# rely on the default here when they don't override it.
func _process(_delta: float) -> void:
	_offscreen_cleanup_check()
	_apply_auto_rotation()


# Rotate so the sprite's "up" (- y) points along the current velocity.
# Tiny moves (under a pixel/frame) are skipped to avoid jitter when the
# enemy is stationary or anchor-following without a real velocity.
func _apply_auto_rotation() -> void:
	if not auto_rotate or _dying:
		return
	if not _rot_init:
		_last_position = global_position
		_rot_init = true
		return
	var delta_pos: Vector2 = global_position - _last_position
	_last_position = global_position
	if delta_pos.length_squared() < 0.04:  # < 0.2px/frame ~= stationary
		return
	# Sprites face up (north); atan2 returns 0 = east. Add PI/2 so
	# velocity (0, +1) → south → rotation = PI (sprite points down).
	rotation = delta_pos.angle() + PI * 0.5


func _offscreen_cleanup_check() -> void:
	if _dying:
		return
	match offscreen_mode:
		OffscreenMode.NONE:
			return
		OffscreenMode.CYCLE_BOTTOM:
			# Only the bottom triggers anything; subclasses override
			# _on_offscreen() (enemy_core does this for its parallax cycle).
			var sz_b: Vector2 = get_viewport_rect().size
			if global_position.y > sz_b.y + offscreen_margin:
				_on_offscreen()
		OffscreenMode.FREE_ANY_EDGE:
			var sz_a: Vector2 = get_viewport_rect().size
			if global_position.y > sz_a.y + offscreen_margin \
				or global_position.y < -offscreen_margin \
				or global_position.x < -offscreen_margin \
				or global_position.x > sz_a.x + offscreen_margin:
				_leave()
		OffscreenMode.FREE_OPPOSITE_SIDE:
			var sz_s: Vector2 = get_viewport_rect().size
			if global_position.x < -offscreen_margin \
				or global_position.x > sz_s.x + offscreen_margin:
				_leave()


# Hook for subclasses that want custom behavior on the bottom exit
# (enemy_core's parallax fly-back). Default: free the enemy.
func _on_offscreen() -> void:
	_leave()


# Treat as a clean leaver — queue_frees without emitting died. WaveDirector
# gates on group presence (post-queue_free the node leaves the group), so no
# signal is needed. Emitting died(0) would falsely bump kill counters,
# trigger camera trauma, and pollute codex stats (Cody, 2026-05-19 playtest).
func _leave() -> void:
	if _dying:
		return
	_dying = true
	queue_free()


# ---- Shield ring helpers (used when max_shield > 0) --------------------

func _setup_shield_ring() -> void:
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.85)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)
	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1)
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_ring.size = Vector2(shield_ring_size, shield_ring_size)
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
	_shield_alpha_tween.tween_method(func(v): _shield_mat.set_shader_parameter("alpha", v), current, target, duration)


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
