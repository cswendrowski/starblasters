extends RefCounted

# EnemyDeathFx (Roman 2026-07-07) — the enemy-death VISUAL pipeline, extracted out of
# enemy_base.explode() so the ~380-line death presentation lives in one place (project convention:
# static helpers called as Cls.method(...)). explode() stays the virtual entry point on EnemyBase and
# owns all the GAME-LOGIC (bounty/died signal, component on_death fan-out, firecore routing, shield-ring
# hide, queue_free timing). This module owns only the pixels.
#
# Two paths:
#   classic(enemy, fx_parent)  — the original instant blast + settling dust + downward-drifting debris +
#                                pixelated-burn disintegrate. Cheap (a handful of tweens, no per-frame
#                                controller). Used for hazards, the firecore "ball" death, and MASS-WIPE
#                                deaths (smart-bomb / EM burst clearing dozens at once) where a
#                                multi-second wreck animation per enemy would be far too expensive.
#   styled(enemy, fx_parent, ...) — hands the hull to the DeathEffects controller for the size-gated
#                                auto-pick ("random" style: spinout / flashout / instakill / blow_out /
#                                wreck). The controller REPARENTS + frees the host itself, so a caller
#                                that routes here must NOT also queue_free the enemy (explode() returns
#                                a bool so the caller knows who owns the free + the death beat).
#
# Both preserve the project conventions: explosions are always 1× scale (bigger enemies get MORE blasts,
# not stretched sprites), debris drifts DOWNWARD from frame 0, debris COUNT scales with size but each
# piece stays 1×, and overlays/engine-trails are hard-culled with the death (no lingering).

const ExplosionFxScript = preload("res://scripts/effects/explosion_fx.gd")
const DeathDustScript = preload("res://scripts/effects/death_dust.gd")
const BurnFxScript = preload("res://scripts/effects/burn_fx.gd")
const DeathEffectsScript = preload("res://scripts/effects/death_effects.gd")

# --- Debris strip (Roman 2026-05-18), moved here with the classic pipeline. ---
const DEBRIS_STRIP_TEX = preload("res://graphics/effects/debris.png")
const DEBRIS_FRAME_COUNT: int = 6
const DEBRIS_LIFETIME: float = 1.6
const DEBRIS_DRIFT_BASE: float = 225.0
const DEBRIS_DRIFT_GAIN: float = 400.0
const DEBRIS_BURST_MIN: float = 140.0
const DEBRIS_BURST_MAX: float = 280.0
# Fixed sprite scale regardless of enemy size — only COUNT scales with the enemy (Roman 2026-05-18/19).
const DEBRIS_PIECE_SCALE: float = 1.0
const DEBRIS_SPIN_MIN: float = -8.0
const DEBRIS_SPIN_MAX: float = 8.0
# Gameplay actors (player / live enemies / bullets) render at z_index 0. Every death VFX (debris,
# ember chunks, blast sprites, wreck hulls, smoke/spark trails) sits BELOW that band so a death never
# occludes a live target — playspace clarity under all circumstances (Roman 2026-07-07).
const DEATH_VFX_Z: int = -3


# ── Classic instant-blast death ─────────────────────────────────────────────────────────────────
# The original explode() VFX body: 1×-scale blast(s) (count scales with size), settling dust, a debris
# scatter that drifts down from frame 0, and a pixelated-burn disintegrate from a random hardpoint. The
# enemy still queue_frees itself (the caller owns that + the death beat); this just paints the pixels.
static func classic(enemy: Node2D, fx_parent: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var world: Vector2 = enemy.global_position
	var display_scale: float = float(enemy.get("display_scale")) if "display_scale" in enemy else 1.0
	var variant: String = String(enemy.get("explosion_variant")) if "explosion_variant" in enemy else "default"
	var ex_scene: PackedScene = ExplosionFxScript.scene_for(variant)
	# All classic death VFX (blast sprites + dust + debris) go into a negative-z sink so they render
	# UNDER the gameplay-actor band (z 0) — playspace clarity (Roman 2026-07-07). Explosion instances are
	# z_as_relative=true, so they inherit the sink's depth.
	var sink: Node = _classic_sink(fx_parent)
	# Explosions are always 1× scale; bigger enemies just get MORE blasts with jitter. 16-px chaff = 1,
	# 48-px boss-class = ~4-5, clamped.
	var blast_count: int = clampi(int(round(max(1.0, display_scale * 1.4))), 1, 6)
	if blast_count <= 1:
		ExplosionFxScript.play(world, 1.0, true, sink, ex_scene)
	else:
		ExplosionFxScript.burst(world, blast_count, 12.0 * max(1.0, display_scale * 0.6), 0.06, sink, ex_scene)
	# Settling dust supplement (Roman 2026-05-24): 1px gray particles, count scales with size.
	DeathDustScript.play(world, display_scale, sink)
	# Debris scatter — parent under the same container so the pieces survive the enemy's queue_free.
	spawn_debris(sink, world, display_scale)
	# Burn starts from a random hardpoint marker so the body dissolves from a believable point.
	if enemy.has_node("Sprite2D"):
		var spr: Sprite2D = enemy.get_node("Sprite2D")
		BurnFxScript.apply_burn(spr, 0.45, Color(0, 0, 0, 0), burn_origin_uv(enemy, spr))
	if enemy.has_node("ParticleExplode"):
		enemy.get_node("ParticleExplode").restart()


# ── Styled (DeathEffects size-gated auto-pick) ──────────────────────────────────────────────────
# Hand the hull to a fresh DeathEffects controller. The controller reparents the host into the wreck
# layer / vfx parent, plays the "random" size-gated death, and frees BOTH the host and itself when done.
# Returns the controller so the caller can wire finished() if it wants; the caller must NOT queue_free
# the enemy — DeathEffects owns it now. `travel` = the enemy's velocity going into the kill.
# overkill_ratio = killing-blow hull damage / max_health, threaded into DeathEffects' "random" auto-pick
# so a massively-overkilled hull (big weapon one-shots small chaff) biases toward the punchy instant
# styles (Roman 2026-07-08). Default -1.0 = "read it off the hull": enemy_base.take_hit stashes the
# fatal-hit overkill on _last_hit_overkill, so the existing 5-arg call site keeps working unchanged; a
# host without that property (e.g. the Shader Lab dummy) yields 0.0 → no bias, exactly as before.
static func styled(enemy: Node2D, fx_parent: Node, wreck_parent: Node, bounds: Rect2, travel: Vector2, overkill_ratio: float = -1.0) -> Node:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var ok: float = overkill_ratio
	if ok < 0.0:
		ok = float(enemy.get("_last_hit_overkill")) if "_last_hit_overkill" in enemy else 0.0
	# A direct-kill weapon (Anti-Ship Missile) can force an explicit death style via _forced_death_style;
	# otherwise the size-gated "random" auto-pick runs (overkill-biased above). Roman 2026-07-08.
	var forced: String = String(enemy.get("_forced_death_style")) if "_forced_death_style" in enemy else ""
	var style: String = forced if forced != "" else "random"
	var fx: Node = DeathEffectsScript.new()
	fx_parent.add_child(fx)
	fx.play(enemy, style, {}, travel, {
		"vfx_parent": fx_parent,
		"wreck_parent": wreck_parent,
		"bounds": bounds,
		"overkill_ratio": ok,
	})
	return fx


# A short-lived negative-z container under `fx_parent` that sinks the classic blast/dust/debris below
# the gameplay-actor band (z 0). z_as_relative=false so its own depth is absolute; explosion instances
# parented into it are z_as_relative=true and inherit it. Frees itself after the classic VFX lifetimes
# (blast ~0.5s, debris ~1.6s) so it never leaks.
static func _classic_sink(fx_parent: Node) -> Node:
	if fx_parent == null or not is_instance_valid(fx_parent):
		return fx_parent
	var sink := Node2D.new()
	sink.name = "DeathClassicSink"
	sink.z_index = DEATH_VFX_Z
	sink.z_as_relative = false
	fx_parent.add_child(sink)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(2.5).timeout.connect(sink.queue_free)
	return sink


# ── Debris (moved verbatim from enemy_base) ─────────────────────────────────────────────────────
static func spawn_debris(parent: Node, world_pos: Vector2, scale_factor: float) -> void:
	# Piece count scaled by enemy size. 16-px chaff → ~3 pieces, 48-px elite → ~9. Clamped.
	var count: int = clampi(int(round(2.0 + scale_factor * 2.3)), 2, 12)
	for i in count:
		_spawn_debris_piece(parent, world_pos, scale_factor)


static func _spawn_debris_piece(parent: Node, world_pos: Vector2, _scale_factor: float) -> void:
	var s := Sprite2D.new()
	s.texture = DEBRIS_STRIP_TEX
	s.hframes = DEBRIS_FRAME_COUNT
	s.vframes = 1
	s.frame = randi() % DEBRIS_FRAME_COUNT
	s.scale = Vector2.ONE * DEBRIS_PIECE_SCALE
	s.global_position = world_pos
	s.rotation = randf_range(0.0, TAU)
	# Death VFX renders UNDER gameplay actors (player/enemies/bullets sit at z 0) for playspace
	# clarity — debris never occludes a live target (Roman 2026-07-07).
	s.z_index = DEATH_VFX_Z
	s.z_as_relative = false
	parent.add_child(s)
	var spin: float = randf_range(DEBRIS_SPIN_MIN, DEBRIS_SPIN_MAX)
	# Burst direction biased to the LOWER hemisphere (Roman 2026-05-18): the enemy was already moving
	# down when it died, so debris scatters outward AND immediately heads down — no "frozen then falls"
	# beat. 0=right, PI/2=down, PI=left. Tiny clamp off the horizontal so a piece doesn't go perfectly
	# sideways.
	var burst_angle: float = randf_range(0.10, PI - 0.10)
	var burst_speed: float = randf_range(DEBRIS_BURST_MIN, DEBRIS_BURST_MAX)
	var burst_vel: Vector2 = Vector2(cos(burst_angle), sin(burst_angle)) * burst_speed
	# X (lateral scatter): pops out fast then plateaus. Y (downward): accelerates over the full
	# lifetime — burst contributes the initial Y, drift compounds it. TRANS_QUAD ease_in mimics gravity.
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


# Pick a random hardpoint marker (engine / muzzle / turret / cannon) and return its UV on the Sprite2D
# so the death burn starts from that point instead of always the centre (Roman 2026-06-11). Falls back
# to centre if there are no markers.
static func burn_origin_uv(enemy: Node, spr: Sprite2D) -> Vector2:
	if spr == null or not is_instance_valid(spr) or spr.texture == null:
		return Vector2(0.5, 0.5)
	var markers: Array = []
	for pat in ["Engine*", "Muzzle*", "Cannon*", "Turret*"]:
		for m in enemy.find_children(pat, "Marker2D", true, false):
			if m is Node2D:
				markers.append(m)
	if markers.is_empty():
		return Vector2(0.5, 0.5)
	var mk: Node2D = markers[randi() % markers.size()]
	var lp: Vector2 = spr.to_local(mk.global_position)
	var uv: Vector2 = Vector2(0.5, 0.5) + lp / spr.texture.get_size()
	return uv.clamp(Vector2(0.05, 0.05), Vector2(0.95, 0.95))
