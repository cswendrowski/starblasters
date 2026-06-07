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

signal died(value: int)
# Emitted when hull health changes (combat overhaul M6a.1). INERT scaffolding for a
# future shared HP bar / RunStats; bosses keep their own hull_changed. Emit on change.
signal health_changed(current: int, max: int)

enum OffscreenMode { CYCLE_BOTTOM, FREE_ANY_EDGE, FREE_OPPOSITE_SIDE, NONE }

@export var max_health: int = 1
@export var bounty_value: int = 5
@export var max_shield: int = 0
@export var shield_ring_size: float = 28.0
# Weapon multipliers (M6b): per-enemy scalars applied to spawned bullets by
# shoot_pattern (faction weapon_mods + sector modifiers compound into these — they
# *= , not = ). bullet_speed clamps to the clarity ceiling at spawn. fire-rate is a
# separate axis (the fire_interval scaling on enemy_core).
@export var bullet_speed_mult: float = 1.0
@export var bullet_damage_mult: float = 1.0
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
# Whether this enemy gets the "ship" presentation VFX: the parallax ground
# shadow + the damage-overlay shader (sprite darkens/frays as HP drops).
# Defaults true — every ship qualifies. NON-ships opt out: mines, bomblets,
# and asteroids set this false (they explode on death rather than visibly
# degrading, and have no hull to cast a ship shadow). Bosses also opt out —
# their .tscns carry bespoke art + their own presentation. This is a SEPARATE
# axis from auto_rotate: ships that drive their own facing (gunship's lateral
# sweep, turrets, cruisers, the aim-at-player beamer) keep auto_rotate=false
# but still want the ship VFX. (Previously both were gated on auto_rotate,
# which silently stripped these effects from every fixed-facing ship.)
@export var has_ship_vfx: bool = true

# --- Identity (combat overhaul, Roman 2026-06-03) ---
# Canonical enemy identity. INERT today: declared so the spawn materializer,
# the lane conductor (tier -> render-plane), and a future RunStats accumulator
# can read structured fields instead of scene_path string-matching. Populated
# progressively (tier/category first, faction with the faction system). Bespoke
# scenes (bosses, asteroids, mines) may self-declare these in their .tscn.
# See docs/combat_construction_plan_2026-06-03.md §7.1.
enum Category { UNKNOWN, CHAFF, ELITE, MINE, ASTEROID, BOSS, PROJECTILE }
@export var chassis: StringName = &""       # silhouette = behavior (e.g. &"dart")
@export var faction: StringName = &""        # color = stat/posture (e.g. &"military")
@export var tier: int = -1                   # Roster.Tier rank; -1 = unset
@export var category: Category = Category.UNKNOWN
# Render plane / altitude bucket. 0 = on the deck (default = current draw order).
# Free-movers/bosses/crossers map to a higher plane in M2 (lane spec §1.10).
@export var render_plane: int = 0

# --- Behavior components (combat overhaul M6a.1, m6 design §3/§19) ---
# A list of small Resources (Shield, Emitter, DeathEffect, …) — the third composition
# axis. Duplicated per-instance at spawn; enemy_base fans out on_start/on_hit/on_death/
# on_leave, enemy_core ticks on_process. INERT until something assigns it (conversions,
# faction overlays) — an empty list is a no-op on every hook.
# UNTYPED `Array` on purpose: the materializer/roster assign this programmatically, and
# assigning an untyped array literal to a typed `Array[Resource]` export is a RUNTIME
# crash in GDScript (not caught by parse_check). Untyped = any assignment is safe.
@export var components: Array = []
var _components: Array = []

# Allow this enemy to leave through the screen sides without being
# clamped back into the playfield. Patterns (side_traverse, side_cut,
# advance_retreat, top_dive) set this to true. Declared on the base so
# the dynamic-assignment in patterns lands on a real property.
var allow_side_exit: bool = false

# Muzzle markers (Roman, 2026-05-31). Resolved lazily on first use from
# Marker2D descendants named `Muzzle*` / `cannon_*` (case-insensitive),
# EXCLUDING mount points named `turret_base` / `turret_mount`. Sorted by
# NAME ascending so MuzzleL precedes MuzzleR and cannon_left precedes
# cannon_right regardless of tree/child order (weaver's markers are nested
# under CollisionShape2D). The alternation index lives on the ENEMY INSTANCE
# — never on a shoot_pattern Resource (Resources are shared across all
# instances of a pattern, so per-enemy state there would corrupt).
var _muzzles: Array = []          # Array[Marker2D], resolved + name-sorted
var _muzzles_resolved: bool = false
var _muzzle_idx: int = 0

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
	# Behavior components: duplicate per-instance, then fire on_start AFTER the spawner
	# positions us (deferred so it lands after start(pos), uniformly for every enemy
	# type). No-op while components is empty.
	_init_components()
	if not _components.is_empty():
		call_deferred("_components_start")
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
	# Engine flame trail. Ship-only — gated on has_ship_vfx (NOT auto_rotate,
	# which is about facing): a fixed-facing ship still wants its presentation.
	if has_ship_vfx:
		# Engine-flame glow disabled 2026-05-30 pending a unified engine-effect
		# overhaul (Roman) — EnemyEngineFxScript stays preloaded for reuse.
		# Ground-shadow on the top parallax layer.
		ParallaxShadowScript.attach(self)
	# Damage overlay shader (Roman, 2026-05-18): darken + fray the sprite
	# as health drops. Ships only (has_ship_vfx gate) — mines, asteroids,
	# bomblets explode on death rather than scaling damage.
	if has_ship_vfx and has_node("Sprite2D"):
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
	var lvl: float = clamp(1.0 - float(health) / float(max_health), 0.0, 0.75)
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
	# Behavior components participate in the damage pipeline (Shield / armor / reflect)
	# before the hull subtraction; on_hit returns the REMAINING damage (m6 §3.1). No-op
	# while components is empty.
	var routed: int = _components_hit(damage)
	if routed <= 0:
		hit()
		return false
	var effective_dmg: int = max(1, int(round(float(routed) * (1.0 - damage_reduction))))
	health -= effective_dmg
	health_changed.emit(health, max_health)
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
	_components_death()
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

# True when this enemy is in a transient "recycling" state (leaving the field
# to re-enter for another pass). The director's wave-ADVANCE gate ignores such
# enemies so a lone recycler doesn't stall the next wave. Subclasses override.
# The final level-clear gate stays strict (counts everyone) so a level never
# ends with a recycler still on-screen. (Roman 2026-06-01)
func is_recycling() -> bool:
	return false


# Cheap player lookup. Returns null if the player isn't in the scene tree
# yet (very early in level start) or has been freed (post-death).
func find_player() -> Node:
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null


# ---- Behavior components (M6a.1) ---------------------------------------
# Duplicate authored components per-instance + fan out lifecycle events. Hooks are
# duck-typed (a component need only implement what it uses). enemy_core ticks
# on_process via _tick_components(); event hooks fire for every enemy type.
func _init_components() -> void:
	_components = []
	for c in components:
		if c != null:
			_components.append(c.duplicate())


func _components_start() -> void:
	if _dying:
		return
	for c in _components:
		if c.has_method("on_start"):
			c.on_start(self)


func _tick_components(delta: float) -> void:
	if _dying:
		return
	for c in _components:
		if c.has_method("on_process"):
			c.on_process(self, delta)


# Route incoming damage through each component's on_hit; returns the damage remaining
# after absorption/reduction (<=0 = fully absorbed).
func _components_hit(damage: int) -> int:
	var d: int = damage
	for c in _components:
		if c.has_method("on_hit"):
			d = int(c.on_hit(self, d))
			if d <= 0:
				return 0
	return d


func _components_death() -> void:
	for c in _components:
		if c.has_method("on_death"):
			c.on_death(self)


func _components_leave() -> void:
	for c in _components:
		if c.has_method("on_leave"):
			c.on_leave(self)


# ---- Muzzle resolution -------------------------------------------------
# Lazily find + cache all Marker2D descendants whose name marks them as a
# muzzle. Mount points (turret_base / turret_mount) are sprite anchors, NOT
# muzzles, so they're excluded. Sorted by name ascending so two-muzzle
# enemies fire in a stable L→R order independent of scene tree layout.
func _resolve_muzzles() -> void:
	if _muzzles_resolved:
		return
	_muzzles_resolved = true
	_muzzles = []
	# find_children returns Variant — never use := on it.
	var markers: Array = find_children("*", "Marker2D", true, false)
	for node in markers:
		var m: Marker2D = node as Marker2D
		if m == null:
			continue
		var lname: String = m.name.to_lower()
		if lname == "turret_base" or lname == "turret_mount":
			continue
		if lname.begins_with("muzzle") or lname.begins_with("cannon"):
			_muzzles.append(m)
	# Stable ordering by name (MuzzleL < MuzzleR, cannon_left < cannon_right).
	_muzzles.sort_custom(func(a, b): return String(a.name) < String(b.name))


# True when this enemy has at least one resolved muzzle marker.
func has_muzzles() -> bool:
	_resolve_muzzles()
	return _muzzles.size() > 0


# Global position of the NEXT muzzle, cycling the per-instance index so
# two-muzzle enemies alternate L/R/L/R. Falls back to the enemy center when
# there are no muzzles.
func next_muzzle_pos() -> Vector2:
	_resolve_muzzles()
	if _muzzles.is_empty():
		return global_position
	var m: Marker2D = _muzzles[_muzzle_idx]
	_muzzle_idx = (_muzzle_idx + 1) % _muzzles.size()
	return m.global_position


# All muzzle global positions (for pair / simultaneous fire). Empty when
# there are no muzzles.
func all_muzzle_pos() -> Array:
	_resolve_muzzles()
	var out: Array = []
	for node in _muzzles:
		var m: Marker2D = node as Marker2D
		if m != null:
			out.append(m.global_position)
	return out


# ---- Nose aiming (shared facing-gated fire) ----------------------------
# Standard helper for "fire only when my nose is actually pointed at the
# target," so an enemy does a proper head-on pass instead of squirting bullets
# sideways while the hull faces elsewhere. Used by the Strafer; reusable by any
# enemy whose sprite has a meaningful front (the sprite TOP / local -Y is the
# nose, per the project's sprite convention).

# World-space unit vector the sprite's NOSE points along. Works whether the
# enemy auto-rotates to its heading or drives `rotation` itself (turrets, the
# aim-at-player gunship) — it reads the live rotation either way.
func nose_dir() -> Vector2:
	return Vector2.UP.rotated(global_rotation)

# Ray-from-nose hit test: true when a ray cast forward from the nose passes
# within `radius` of `target` (target treated as a circle). Reads as: "if I
# fire straight ahead RIGHT NOW, the shot goes through `target`." Gate firing on
# this — when it's true, "forward" and "at the target" coincide, so bullets fly
# out the nose and still connect. `max_range` (px, measured ALONG the nose)
# optionally bounds engagement distance; pass <= 0 to disable the range cap.
func nose_ray_hits(target: Vector2, radius: float, max_range: float = 0.0) -> bool:
	var to_t: Vector2 = target - global_position
	var fwd: Vector2 = nose_dir()
	var ahead: float = to_t.dot(fwd)
	if ahead <= 0.0:
		return false                              # target is behind the nose
	if max_range > 0.0 and ahead > max_range:
		return false                              # beyond engagement range
	return (to_t - fwd * ahead).length() <= radius  # perpendicular miss <= radius

# Convenience wrapper: is the nose lined up on the player?
func nose_ray_hits_player(radius: float, max_range: float = 0.0) -> bool:
	var p := find_player() as Node2D
	return p != null and nose_ray_hits(p.global_position, radius, max_range)


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
			# The bottom exit always triggers the recycle hook; subclasses
			# override _on_offscreen() (enemy_core does this for its parallax
			# cycle). Enemies that break off SIDEWAYS — allow_side_exit patterns
			# like the Skirmisher's advance_retreat BREAK phase — used to wait
			# until their slow Y descent finally crossed the bottom margin (the
			# Skirmisher's 19.2 px/s drift = ~14 s of off-screen loiter before it
			# recycled). Treat a full side exit as an off-screen trigger too, so
			# the recycle fires promptly and consistently regardless of which edge
			# the enemy actually left through. We deliberately do NOT watch the
			# TOP edge here: patterns legitimately spawn/retreat near y=0, so a
			# top trigger would misfire — sideways drift is the real culprit.
			# Viewport edges (not playfield band) so in-band pong/overshoot from
			# side-cutters never trips this; only a genuine off-screen exit does.
			var sz_b: Vector2 = get_viewport_rect().size
			if global_position.y > sz_b.y + offscreen_margin:
				_on_offscreen()
			elif allow_side_exit and (global_position.x < -offscreen_margin \
				or global_position.x > sz_b.x + offscreen_margin):
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
	_components_leave()
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
