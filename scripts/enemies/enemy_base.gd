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
const BurnFxScript = preload("res://scripts/effects/burn_fx.gd")
const MountBuilder = preload("res://scripts/enemies/mounts/mount_builder.gd")
# Dead-code holdover: the simple max_shield charge + its ring are retired (nothing in the
# live spawn path sets max_shield > 0). Repointed to hex_shield so the only consumer left —
# the preserved-but-unscened enemy_bomber_wing — matches the committed shield (Roman 2026-06-11).
const SHIELD_SHADER = preload("res://graphics/hex_shield.gdshader")

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
# INERT (shield_unification_2026-06-08.md): the simple charge-shield is retired in favour
# of ShieldComponent. Nothing in the live spawn path sets max_shield anymore; `shield`
# (below) is kept only as a harmless target for smart_bomb's legacy shield-strip guard.
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
# --- Locomotion stat block (chassis-owned kinematics; locomotion refactor 2026-06-19) ---
# Movement patterns express SHAPE only and read these for SCALE (movement_pattern.gd accessors).
# Resolved per-spawn from the roster (size base rung + engine modifier) in director._spawn_enemy;
# a per-scene .tscn may also author them. An unset value (0, or depth_bp < 0) falls back to the
# pattern's medium default, so bosses/mines/hazards WITHOUT a block keep working unchanged.
# `weight` is the inertia/turn mass that `display_scale` used to stand in for — display_scale is
# now purely visual.
@export var move_speed: float = 0.0   # absolute px/s, ALWAYS a clarity rung once resolved
@export var weight: float = 1.0       # mass: inertia smoothing + turn/accel damping
@export var turn_rate: float = 0.0    # deg/s base steering rate (jet / omni / inertial)
@export var accel: float = 0.0        # px/s² base acceleration (charge / beeline / loiter-exit)
@export var depth_bp: float = -1.0    # DEFAULT engagement depth (Zones.band_progress 0..1); <0 = pattern default
# Locomotion capability flags (Roman 2026-06-21) — OPT-IN (default false = face raw velocity, the
# legacy auto-rotate). They decouple FACING from travel in _apply_auto_rotation:
#   omni   — face the PLAYER while moving (omni-directional thrust; stays on target as it slides).
#   strafe — slide left/right WITHOUT turning (lateral velocity dropped from facing; sweeping loiter).
#   retro  — fly BACKWARD without turning (reverse/upward velocity dropped from facing; skirmish loops).
# strafe + retro compose: a unit with both holds a fixed forward (downward) facing however it travels.
@export var omni: bool = false
@export var strafe: bool = false
@export var retro: bool = false
# Death-explosion variant (ExplosionFx.VARIANTS key — "default" / "small_circle" / …).
# The enemy dev tool + per-enemy scenes set this; explode() resolves it to a scene.
@export var explosion_variant: String = "default"
@export var offscreen_mode: int = OffscreenMode.CYCLE_BOTTOM
# True once the enemy first reaches the visible area (y >= 0). Gates the FREE_ANY_EDGE top-edge cull
# so a formation row pre-stacked above the screen (authored_patterns) isn't freed before it descends
# in; a genuine top EXIT (after entry) still frees.
var _entered_playfield: bool = false
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

# 1px black outline on the hull (Roman 2026-06-07) — the "shootable foreground"
# read, extended from asteroids to every enemy SHIP. Default on; opt OUT for the
# exceptions (firecores, mine munitions, asteroids-have-their-own). Missiles /
# rockets / projectiles aren't EnemyBase so they're excluded by construction; the
# glow-mask is a separate node, not the hull "Sprite2D", so it's untouched.
# enemy_core hides the outline while an enemy is recycling / faux-parallax.
@export var wants_outline: bool = true

# Opt out of the corporate faction's Shield overlay (Roman 2026-06-07): a corporate
# unit that should NOT be shielded (e.g. the corporate dart c_dart) sets this true.
# Checked in Factions.apply when adding the corporate shield component.
@export var faction_shield_exempt: bool = false

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

# Firing mounts (Roman 2026-06-16): extra guns/turrets/launchers/beams beyond the hull
# `shoot_pattern`, as MountSpec resources. Realized at spawn by MountBuilder (turrets/beams become
# child nodes; gun/launcher mounts become MountComponents appended to _components). UNTYPED for the
# same reason as `components` above (programmatic assignment from roster/director/bench).
@export var mounts: Array = []

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
# Recent world velocity (px/s), updated each movement frame. Read by _die_as_wreck so a wreck
# preserves the enemy's motion at the moment of death before drifting into the fall (Roman 2026-06-10).
var _last_move_vel: Vector2 = Vector2.ZERO
var _rot_init: bool = false

# Cached viewport size — used by subclasses for off-screen checks and side
# clamps. Set in _ready() (not @onready) so subclasses can use it from their
# own _ready() without ordering concerns.
var screensize: Vector2 = Vector2(800, 1000)


func _ready() -> void:
	screensize = get_viewport_rect().size
	health = max_health
	# Allow rapid $EnemyShoot.play() calls to overlap so each shot is
	# audible to completion (Roman feedback 2026-05-23). ($EnemyDie is retired —
	# deaths sound via the distance-based ExplosionSfx in explode(); see there.)
	var SfxCls = load("res://scripts/effects/sfx.gd")
	# Route scene-embedded SFX (EnemyShoot etc.) onto the SFX bus so the
	# Options "Sound Volume" slider controls them.
	SfxCls.route_children_to_sfx(self)
	if has_node("EnemyShoot"):
		SfxCls.ensure_polyphony($EnemyShoot, 4)
	# Defensive group registration. Every enemy .tscn already declares
	# `groups=["enemies"]` on its root; this is the safety net for any
	# enemy that was instantiated from script without a scene.
	if not is_in_group("enemies"):
		add_to_group("enemies")
	# Behavior components: duplicate per-instance, then fire on_start AFTER the spawner
	# positions us (deferred so it lands after start(pos), uniformly for every enemy
	# type). No-op while components is empty.
	_init_components()
	_attach_mounts()   # BEFORE the deferral so gun/launcher mounts get on_start too
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
		# Progressive damage tells. Deferred so the spawner's display_scale (director sets
		# enemy.scale after instancing) is applied before we measure the size bucket + place
		# the spark/burn markers at their final world positions.
		# DEFAULT-OFF (lab-only, reverted 2026-06-17 for crashes). Re-enabled only when the crash
		# stress test flips ShipDamageTells.live_enabled — see scripts/dev/crash_loop_runner.gd.
		if _ShipDamageTells.live_enabled:
			call_deferred("_attach_damage_tells")
	# 1px black hull outline (Roman 2026-06-07). Separate behind-node (NOT a
	# material on the hull — that slot holds the damage shader, and the hull is a
	# 2-frame sheet). Only the visible hull "Sprite2D" is outlined; the glow-mask
	# and any decorative cores are other nodes. Opt-out via wants_outline.
	if wants_outline and has_node("Sprite2D") and $Sprite2D.visible:
		_OutlineFx.apply($Sprite2D)
	# Engine glowmask glow (Roman 2026-06-20): push any "GlowMask" overlay HDR-bright with the
	# firecore's glow settings so the WorldEnvironment bloom lights it. See _setup_glowmask.
	_setup_glowmask()
	# Yellow engine trail (Roman 2026-06-07): any enemy that places Engine* markers
	# (Engine / EngineL / EngineR / EngineL2 ... anywhere in its scene) gets a trailing
	# exhaust streak per marker via the shared EngineTrailFx — no per-enemy code.
	_attach_engine_trail()


const _OutlineFx = preload("res://scripts/effects/outline_fx.gd")
const _EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
const _ShipDamageTells = preload("res://scripts/effects/ship_damage_tells.gd")
var _engine_trail: Node = null
var _damage_material: ShaderMaterial = null
# Progressive battle-damage tells (sparks → burning trails → disintegrate + per-size death VFX).
# Attached for ship-vfx enemies only (bosses/hazards set has_ship_vfx=false); drives the overlay +
# tells off take_hit and owns the normal-path death blast. Null until the deferred attach lands.
var _dmg_tells: Node = null
# The hit-flash tween. Tracked so _die_as_wreck can KILL it before reparenting the hull — otherwise
# its first idle-step (the burst hits during physics) re-snaps the already-reparented wreck to white
# flash_strength after _die_as_wreck zeroed it (Roman 2026-06-10 white-carryover fix).
var _flash_tween: Tween = null


# Find Engine* markers (recursive — they may sit under CollisionShape2D) and attach a
# shared yellow trail. No-op when the enemy has no engine markers.
func _attach_engine_trail() -> void:
	var markers: Array = find_children("Engine*", "Marker2D", true, false)
	if markers.is_empty():
		return
	_engine_trail = _EngineTrailFx.new()
	add_child(_engine_trail)
	_engine_trail.setup(self, markers)


# Pause/resume the engine exhaust (recycle = faux-parallax, death = stop emitting).
func set_engine_trail_emitting(v: bool) -> void:
	if _engine_trail != null and is_instance_valid(_engine_trail):
		_engine_trail.set_emitting(v)
var _shield_ring: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_alpha_tween: Tween = null
var _shield_hit_tween: Tween = null


# Attach the ShipDamageTells driver (self_explode=false — take_hit drives it, explode() decides who
# owns the death blast). It reuses the damage material installed above, so the overlay sensitivity it
# sets and our hit-flash share one material. No-op if the enemy died/freed before the deferral lands.
func _attach_damage_tells() -> void:
	if _dying or not is_instance_valid(self) or not has_node("Sprite2D"):
		return
	var spr := $Sprite2D as Sprite2D
	var ss: float = _tells_size_scale(spr)
	var tells: Node2D = _ShipDamageTells.new()
	tells.self_explode = false
	add_child(tells)
	tells.setup(self, spr, ss, _ShipDamageTells.cfg_for_size(ss))
	_dmg_tells = tells


# Ship size_scale = effective sprite pixel size / 16 (mirrors the Shader Lab Ship-Damage panel), used
# to pick the small/medium/large tell preset. global_scale composes the ship's display_scale.
func _tells_size_scale(spr: Sprite2D) -> float:
	if spr != null and is_instance_valid(spr) and spr.texture != null:
		var fsz: Vector2 = spr.texture.get_size()
		if spr.hframes > 1:
			fsz.x /= float(spr.hframes)
		if spr.vframes > 1:
			fsz.y /= float(spr.vframes)
		var gs: Vector2 = spr.global_scale
		var px: float = maxf(fsz.x, fsz.y) * maxf(absf(gs.x), absf(gs.y))
		return clampf(px / 16.0, 0.6, 3.5)
	return clampf(display_scale, 0.6, 3.5)


func _install_damage_material(spr: Sprite2D) -> void:
	if spr == null or spr.material != null:
		return  # don't stomp a pre-existing material (hologram, etc.)
	var mat := ShaderMaterial.new()
	mat.shader = DamageOverlayShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
	mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	# Shader-Lab-tuned look (Roman 2026-06-11 Damage tuner). sensitivity stays HP-driven (see
	# _update_damage_visual); these are the static appearance params + colours.
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	spr.material = mat
	_damage_material = mat


func _update_damage_visual() -> void:
	if _damage_material == null:
		return
	if max_health <= 0:
		return
	# Ramp the damage overlay linearly in MISSING health: 0 at full HP, 0.6 at
	# 1 HP (Roman 2026-06-10). Denominator guards a 1-HP enemy from /0.
	var denom: float = maxf(float(max_health) - 1.0, 1.0)
	var lvl: float = clampf(0.6 * (float(max_health) - float(health)) / denom, 0.0, 0.6)
	_damage_material.set_shader_parameter("sensitivity", lvl)


# White hit-flash. On ships the damage material owns the sprite's material slot, so we
# drive its flash_strength uniform (and the per-hit damage update lands during the flash
# for a seamless reveal). Enemies without a damage material use the standalone flash.
func _flash_hit() -> void:
	if _dying:
		return
	if _damage_material != null:
		_damage_material.set_shader_parameter("flash_strength", 1.0)
		var mat := _damage_material
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(
			func(v: float):
				if is_instance_valid(mat):
					mat.set_shader_parameter("flash_strength", v),
			1.0, 0.0, 0.12)
	elif has_node("Sprite2D"):
		var HF = load("res://scripts/effects/hit_flash_fx.gd")
		HF.flash($Sprite2D, HF.FLASH_WHITE)


# ---- Bullet hit pipeline -----------------------------------------------

# Single damage entry point. Returns true if the hit was fatal so callers
# can act on it (e.g. award bounty, spawn pickup) without parsing the
# death signal.
func take_hit(damage: int = 1) -> bool:
	if _dying:
		return false
	# Off-screen / recycling enemies are not valid targets — a bullet or bomb wave shouldn't kill an
	# enemy that's mid-parallax-flyback or fully off the screen (Roman 2026-06-10). They re-arm as
	# targets the moment they re-enter. (Bullets route here; the smart-bomb wave guards separately.)
	if is_recycling() or is_fully_offscreen():
		return false
	# Run-summary Phase 2: a shot connected with a valid target (counts even if a shield
	# absorbs it — the shot still landed). accuracy = shots_hit / shots_fired; pierce/AoE
	# and the occasional ram/smart-bomb hit can push it past 100% (accepted).
	var _rs = get_node_or_null("/root/Run")
	if _rs != null:
		_rs.stat_add("shots_hit", 1)
	# Shields are unified onto ShieldComponent (shield_unification_2026-06-08.md): the
	# simple max_shield/shield charge is retired, so all hits flow through the component
	# pipeline (_components_hit) where a ShieldComponent — if present — absorbs them.
	# White flash on every non-shield hit (Roman 2026-06-08). Ships carry the damage
	# material in their only material slot, so the flash rides ON that material; other
	# enemies use the standalone hit_flash shader.
	_flash_hit()
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
	# Drive the damage tells (overlay sensitivity + progressive sparks / burning trails) — LIVE damage
	# only. enemy_base.explode() owns the death VFX (the tell death-delegation was reverted 2026-06-17),
	# so cap below 1.0 here: a lethal hit skips this and falls through to explode(). Enemies without
	# tells use the plain overlay.
	if _dmg_tells != null and is_instance_valid(_dmg_tells):
		if health >= 1:
			_dmg_tells.set_damage(clampf(1.0 - float(health) / maxf(1.0, float(max_health)), 0.0, 0.999))
	else:
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
	# Two SEPARATE disabled-wreck death styles (Roman 2026-06-10), both routing the hull into the
	# wreck layer as a burning, smoking, falling disabled wreck. They differ only in trigger + exit
	# resolution; both require a wreck layer (else they fall through to the normal explosion below):
	#   1. EM-TORP DISABLE — meta "death_style"="disabled_em" (set by the EM burst). 20% explode now
	#      / 80% disable; disabled hulls just DROP off-screen at the exit zone (exit chance 0.0).
	#   2. GENERAL DISABLE MODE — for NON-EM deaths, opted in via Run meta "disable_deaths". The kill
	#      always disables, and at the exit zone 70% explode / 30% fall off (exit chance 0.70).
	if has_meta("death_style") and String(get_meta("death_style")) == "disabled_em":
		remove_meta("death_style")
		var wlayer_em: Node = get_tree().get_first_node_in_group("wreck_layer") if is_inside_tree() else null
		if wlayer_em != null and is_instance_valid(wlayer_em) and randf() >= 0.20:
			_die_as_wreck(wlayer_em, 0.0)
			return
	elif _should_general_disable():
		var wlayer_g: Node = get_tree().get_first_node_in_group("wreck_layer")
		if wlayer_g != null and is_instance_valid(wlayer_g):
			_die_as_wreck(wlayer_g, 0.70)
			return
	if _shield_ring and is_instance_valid(_shield_ring):
		_shield_ring.visible = false
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_components_death()
	# Firecore-dropper explosion routing (Roman 2026-06-10): any enemy CARRYING a
	# firecore-tagged emitter (zealot in-scene components AND the zealot faction overlay
	# added at spawn) plays the "ball" explosion when it dies WITHOUT dropping a core, and
	# the normal explosion when a core drops. Detected off the tagged component itself —
	# not scene metadata — so the faction-overlay path routes correctly (review fix
	# 2026-06-10; the old has_meta check missed overlay-only droppers). Must run AFTER
	# _components_death() fires the emitters.
	if _has_emitter_tagged("firecore"):
		explosion_variant = "default" if did_emit_tagged("firecore") else "ball"
	# Explosions are always 1× scale; bigger enemies just get MORE blasts
	# with random jitter (Roman 2026-05-18). 16-px chaff = 1, 48-px boss-
	# class = ~4-5, clamped to a sane upper bound.
	# Spawn all death VFX into THIS node's own container (get_parent) so they
	# share its coordinate space. In combat that's the main scene (identical to
	# the old root/current_scene parenting); in the hangar's SubViewport preview
	# it's `_world`, which keeps the blasts over the ship instead of the window's
	# top-left corner.
	var fx_parent: Node = _fx_parent()
	# Fade the non-body overlay sprites (glow mask, hull outline, decorative cores) FAST so they don't
	# outlive the disintegrating body, and stop the exhaust (the streak ages out on its own). Both
	# paths want this.
	_fade_death_overlays()
	set_engine_trail_emitting(false)
	# Quiet the progressive damage tells so their emitters stop churning the draw order through the
	# death animation. The tells drive LIVE damage only (overlay + sparks + burn trails); enemy_base
	# owns the death VFX below — the per-enemy tell death-delegation was reverted (Roman 2026-06-17)
	# after it surfaced a render-server draw-index race on the death frame (ShipDebrisEmber absolute-z).
	if _dmg_tells != null and is_instance_valid(_dmg_tells):
		_dmg_tells.quiet()
	var ex_scene: PackedScene = ExplosionFxScript.scene_for(explosion_variant)
	# Explosions are always 1× scale; bigger enemies just get MORE blasts with jitter. 16-px
	# chaff = 1, 48-px boss-class = ~4-5, clamped.
	var blast_count: int = clampi(int(round(max(1.0, display_scale * 1.4))), 1, 6)
	if blast_count <= 1:
		ExplosionFxScript.play(global_position, 1.0, true, fx_parent, ex_scene)
	else:
		ExplosionFxScript.burst(global_position, blast_count, 12.0 * max(1.0, display_scale * 0.6), 0.06, fx_parent, ex_scene)
	# Settling dust supplement (Roman 2026-05-24): 1px gray particles, count scales with size.
	DeathDustScript.play(global_position, display_scale, fx_parent)
	# Debris scatter — parent under the same container so the pieces survive queue_free.
	_spawn_debris(fx_parent, global_position, display_scale)
	# Burn starts from a random hardpoint marker so the body dissolves from a believable point.
	if has_node("Sprite2D"):
		BurnFxScript.apply_burn($Sprite2D, 0.45, Color(0, 0, 0, 0), _burn_origin_uv())
	if has_node("ParticleExplode"):
		$ParticleExplode.restart()
	# Death audio: the scene-embedded $EnemyDie clip is RETIRED (Roman 2026-06-10 — "wire up the
	# new explosion sounds, retire the old ones"). Deaths now sound exclusively through the
	# distance-based ExplosionSfx fired by the ExplosionFx.play/burst calls above; playing the
	# old clip here buried the new ones. The EnemyDie nodes remain in the scenes (inert).
	await get_tree().create_timer(0.5).timeout
	queue_free()


# Disabled-wreck death (Roman 2026-06-10): instead of exploding, steal this enemy's hull Sprite2D
# into the wreck layer as a DISABLED hull — heavy-damaged, on fire + smoking (the player's damage
# tells), tumbling and falling into the backdrop, until it reaches the exit zone and either explodes
# or drops off-screen (decided in wreck_drift). Still counts as a kill (died.emit fires) so bounty +
# level-clear are unaffected. The enemy's other nodes free with the body; the visible ones we want
# to carry (outline, glow) are reparented onto the hull so they can fade/flicker out.
const _WreckDriftScript = preload("res://scripts/effects/wreck_drift.gd")
static var _wreck_seq: int = 0


# Pick a random hardpoint marker (engine / muzzle / turret / cannon) and return its UV
# on the Sprite2D, so the death burn (pixelated_burn `position`) starts from that point
# instead of always the centre (Roman 2026-06-11). Falls back to centre if no markers.
func _burn_origin_uv() -> Vector2:
	if not has_node("Sprite2D"):
		return Vector2(0.5, 0.5)
	var spr: Sprite2D = $Sprite2D
	if spr.texture == null:
		return Vector2(0.5, 0.5)
	var markers: Array = []
	for pat in ["Engine*", "Muzzle*", "cannon_*", "Turret*"]:
		for m in find_children(pat, "Marker2D", true, false):
			if m is Node2D:
				markers.append(m)
	if markers.is_empty():
		return Vector2(0.5, 0.5)
	var mk: Node2D = markers[randi() % markers.size()]
	var lp: Vector2 = spr.to_local(mk.global_position)
	var uv: Vector2 = Vector2(0.5, 0.5) + lp / spr.texture.get_size()
	return uv.clamp(Vector2(0.05, 0.05), Vector2(0.95, 0.95))


# True when this enemy should use the GENERAL disable death (Roman 2026-06-10): opted in via the Run
# meta "disable_deaths" (a test/showcase flag for now; future triggers — a part, a hazard — set the
# same meta). Only real ships qualify — hazards (mines/asteroids) and non-ship units are excluded.
func _should_general_disable() -> bool:
	if is_hazard or not has_ship_vfx:
		return false
	if not has_node("Sprite2D"):
		return false
	if not is_inside_tree():
		return false
	var run: Node = get_node_or_null("/root/Run")
	return run != null and run.has_meta("disable_deaths") and bool(run.get_meta("disable_deaths"))

# Reparent this enemy's hull into the wreck layer as a disabled, burning, falling wreck. WreckDrift
# owns the fire/smoke tells + motion + the exit-zone resolution; `exit_explode_chance` is the fraction
# that explode (vs fall off-screen) at the exit zone — EM-torp disable passes 0.0, the general disable
# mode passes 0.70.
func _die_as_wreck(wlayer: Node, exit_explode_chance: float) -> void:
	_dying = true
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	died.emit(bounty_value)        # kill still counts toward bounty + level-clear
	_components_death()
	set_engine_trail_emitting(false)
	var spr: Node = get_node_or_null("Sprite2D")
	if spr == null or not (spr is Node2D) or not is_instance_valid(wlayer):
		queue_free()
		return
	var s: Node2D = spr
	# Heavy-damage look, NOT pure white (Roman 2026-06-10): KILL the hit-flash tween (it would
	# otherwise run its first idle-step after this and re-snap the reparented wreck to white) then
	# zero the flash and crank the damage-overlay fray to max so the wreck reads as a battered hull.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if s.material is ShaderMaterial:
		var m: ShaderMaterial = s.material
		m.set_shader_parameter("flash_strength", 0.0)
		m.set_shader_parameter("sensitivity", 0.75)
	# Capture transform + motion + emit points (engine markers + hull centre, in world space) BEFORE
	# reparenting; convert to hull-local after.
	var gpos: Vector2 = s.global_position
	var grot: float = s.global_rotation
	var gscl: Vector2 = s.global_scale
	var init_vel: Vector2 = _last_move_vel
	var emit_worlds: Array = [s.global_position]   # hull centre
	for mk in find_children("Engine*", "Marker2D", true, false):
		if mk is Node2D:
			emit_worlds.append((mk as Node2D).global_position)
	# A falling wreck shouldn't cast a ground shadow — the shadow is a child of the sprite, so it
	# would ride along; drop it.
	var sh: Node = s.get_node_or_null("ObliqueShadow")
	if sh != null:
		sh.queue_free()
	# Reparent the hull into the wreck layer (world transform preserved).
	remove_child(s)
	wlayer.add_child(s)
	s.global_position = gpos
	s.rotation = grot
	s.global_scale = gscl
	s.z_index = 0
	var emit_local: Array = []
	for w in emit_worlds:
		emit_local.append(s.to_local(w))
	# The black outline is NOT carried onto the wreck (Roman 2026-06-11: "the outline fade can just
	# be removed, how it was before was fine"). It's a sibling on the enemy and frees with it.
	# Glowmap: enemies with a GlowMask FLICKER it then fade it out as they disable (Roman 2026-06-10).
	# Carry it onto the hull so it tracks the fall, then run a brief flicker -> fade.
	var glow: Node = get_node_or_null("GlowMask")
	if glow != null and glow is Node2D:
		var g_gpos: Vector2 = (glow as Node2D).global_position
		remove_child(glow)
		s.add_child(glow)
		var gl: Node2D = glow
		gl.global_position = g_gpos
		var gtw: Tween = gl.create_tween()
		# Flicker: a few quick dim/bright stutters, then fade out.
		for _i in 3:
			gtw.tween_property(gl, "modulate:a", 0.15, 0.05)
			gtw.tween_property(gl, "modulate:a", 0.9, 0.05)
		gtw.tween_property(gl, "modulate:a", 0.0, 0.3)
		gtw.tween_callback(gl.queue_free)
	# WreckDrift owns the fire/smoke tells (emitted from a random engine marker / centre) + motion +
	# the exit-zone resolution.
	_WreckDriftScript.attach(s, init_vel, _wreck_seq, exit_explode_chance, emit_local)
	_wreck_seq += 1
	queue_free()


# Fade out the overlay sprites that AREN'T the burning hull — glow mask, the 1px
# outline, and any decorative firecore cores — so none of them linger after death.
# Fast (0.15s) so they're gone almost immediately while the body disintegrates.
const _MineBlinkerScript = preload("res://scripts/effects/mine_blinker.gd")
const _GravityGlowScript = preload("res://scripts/effects/gravity_glow.gd")

func _fade_death_overlays() -> void:
	const OVERLAY_FADE := 0.15
	for child in get_children():
		# Effect nodes that own multiple sub-visuals + per-frame logic (mine centre
		# blink, gravity glow) can't be killed by a single modulate tween — stop()
		# them instantly so neither lingers over the explosion.
		var scr: Script = child.get_script()
		if scr == _MineBlinkerScript or scr == _GravityGlowScript:
			child.stop()
			continue
		if not (child is CanvasItem):
			continue
		var nm: String = String(child.name)
		# The Livery layer's screen-darken shader overwrites COLOR (alpha = sprite_tex.a), so a
		# modulate:a fade is IGNORED — it would linger as a dark mask through the ~0.5s death beat
		# (Roman 2026-06-21). Fade the darken EFFECT via the shader's `opacity` uniform instead
		# (mix→screen at 0 = no tint, reveals the disintegrating body); hard-hide as a fallback for
		# any livery without the shader material.
		if nm == "Livery":
			var lmat: Material = (child as CanvasItem).material
			if lmat is ShaderMaterial:
				# Fade the darken EFFECT via the shader's `opacity` uniform (the livery shader ignores
				# modulate:a). Only seed the override if it's missing — apply_livery sets it (0.8); don't
				# snap it back up to full-dark here. Then fade it out from wherever it is.
				var lsm := lmat as ShaderMaterial
				if lsm.get_shader_parameter("opacity") == null:
					lsm.set_shader_parameter("opacity", 0.8)
				var ltw := create_tween()
				ltw.tween_property(lsm, "shader_parameter/opacity", 0.0, OVERLAY_FADE)
			else:
				(child as CanvasItem).visible = false
			continue
		# Engine/tail glow overlays (incl. the bomber's "Glowmap"/"TailGunGlow", which don't follow the
		# GlowMask name) fade out with the body so they don't outlive the disintegration.
		if nm == "GlowMask" or nm == "Glowmap" or nm == "TailGunGlow" or nm == "Outline" or nm.begins_with("FirecoreCore"):
			var tw := create_tween()
			tw.tween_property(child, "modulate:a", 0.0, OVERLAY_FADE)


# Engine glowmask (the body's frame-1 glow-parts overlay) → HDR-bright so the WorldEnvironment bloom
# lights it, by the tuned "engines" multiplier (Roman 2026-06-22). No-op if the scene has no GlowMask.
# The death tweens above only touch modulate:a, so the HDR rgb survives until the fade.
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")

func _setup_glowmask() -> void:
	var gm := get_node_or_null("GlowMask")
	if gm is Sprite2D:
		(gm as Sprite2D).modulate = VfxGlow.prod_hdr("engines")


# The container death VFX (explosions, dust, debris) should spawn into: this
# node's own parent, so they share its coordinate space and outlive its
# queue_free. Falls back to current_scene / root if somehow unparented.
func _fx_parent() -> Node:
	var p: Node = get_parent()
	if p != null and is_instance_valid(p):
		return p
	var cs: Node = get_tree().current_scene
	return cs if cs != null else get_tree().root


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


# True when the enemy is fully outside the visible viewport (by offscreen_margin on any edge) — used
# to reject hits on enemies that aren't on screen (entry-band above the top, exited below/side).
func is_fully_offscreen() -> bool:
	if not is_inside_tree():
		return false
	var vp: Vector2 = get_viewport_rect().size
	var m: float = offscreen_margin
	return position.y < -m or position.y > vp.y + m or position.x < -m or position.x > vp.x + m


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


# Realize `mounts` (MountSpec resources) into live primitives. Turrets/beams become child nodes;
# gun/launcher mounts become fresh MountComponents appended to the live component list so they
# tick (their on_start fires via the same deferred _components_start path as authored components).
func _attach_mounts() -> void:
	if mounts.is_empty():
		return
	for c in MountBuilder.attach_all(self, mounts):
		_components.append(c)


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


# Strip every ShieldComponent down to zero (the EM Torpedo burst calls this before applying its
# shield-ignoring damage). Also drops the legacy simple max_shield charge. (Roman 2026-06-10.)
func break_shields() -> void:
	shield = 0
	for c in _components:
		if c.has_method("break_shield"):
			c.break_shield()


func _components_leave() -> void:
	for c in _components:
		if c.has_method("on_leave"):
			c.on_leave(self)


# True if this enemy CARRIES a tagged EmitterComponent (e.g. "firecore") — regardless of
# whether it has emitted. Drives the dropper-explosion routing in explode().
func _has_emitter_tagged(tag: String) -> bool:
	for c in _components:
		if "tag" in c and "payload" in c and String(c.get("tag")) == tag:
			return true
	return false


# Check if a tagged EmitterComponent (e.g. "firecore") successfully emitted on_death.
# Used by the explosion-variant routing. (on_death always writes _last_emit_succeeded
# fresh — true on a successful roll, false otherwise — so this is never stale.)
func did_emit_tagged(tag: String) -> bool:
	for c in _components:
		if "tag" in c and "payload" in c and "_last_emit_succeeded" in c:
			if String(c.get("tag")) == tag and bool(c.get("_last_emit_succeeded")):
				return true
	return false


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
	# OMNI: keep the nose on the player regardless of travel direction (omni-directional thrust).
	# Done even while stationary so the unit tracks; bypasses the velocity-based facing below.
	# (Dedicated omni patterns like omni_thrust suppress auto_rotate and steer themselves — this
	# branch is the generalization for any other pattern on an omni-capable hull.)
	if omni:
		var pl := find_player()
		if pl != null and pl is Node2D:
			var to_p: Vector2 = (pl as Node2D).global_position - global_position
			if to_p.length_squared() > 1.0:
				rotation = to_p.angle() + PI * 0.5
		return
	if delta_pos.length_squared() < 0.04:  # < 0.2px/frame ~= stationary
		return
	# STRAFE drops the lateral (X) component and RETRO drops the backward (upward, −Y) component from
	# the FACING velocity, so a sliding/reversing unit keeps facing forward instead of turning. When
	# the filtered velocity collapses to ~0 (a pure side-slide or pure reverse) the unit faces straight
	# DOWN (its forward), never snapping sideways or flipping around.
	var fv: Vector2 = delta_pos
	if strafe:
		fv.x = 0.0
	if retro and fv.y < 0.0:
		fv.y = 0.0
	if fv.length_squared() < 0.0001:
		fv = Vector2(0.0, 1.0)
	# Sprites face up (north); atan2 returns 0 = east. Add PI/2 so
	# velocity (0, +1) → south → rotation = PI (sprite points down).
	rotation = fv.angle() + PI * 0.5


func _offscreen_cleanup_check() -> void:
	if _dying:
		return
	# Once the enemy first reaches the visible area, allow the FREE_ANY_EDGE top-edge cull (below) to
	# fire on a genuine top exit. Until then a row pre-stacked above the screen is still descending IN.
	if not _entered_playfield and global_position.y >= 0.0:
		_entered_playfield = true
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
				or (_entered_playfield and global_position.y < -offscreen_margin) \
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


# ---- Shield ring helpers — RETIRED (shield_unification_2026-06-08.md) ---
# The simple max_shield/shield charge + its ring are gone; shields are now a
# ShieldComponent (which carries its own ring). The `_shield_*` vars + SHIELD_SHADER
# const are retained only because the UNWIRED legacy enemy_bomber_wing.gd still draws
# its own ring through them; nothing in the live spawn path sets max_shield anymore.
