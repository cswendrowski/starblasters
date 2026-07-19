extends "res://scripts/enemies/enemy_base.gd"

# Hazard asteroid. Slow drift, modest HP, no shoot, no bounty. Damages the
# player on contact but isn't actively hunting.

# 320×400 res rework — speeds halved. Roman 2026-06-02: +20% (55 → 66) for the
# denser/faster asteroid-field hazard pass.
@export var drift_speed: float = 60.0
@export var damage_on_collide: int = 2
# Lateral drift mode (Roman 2026-06-23): "drift_all" (default — free band drift, the historical
# behavior), "drift_lane", "drift_adjacent", or "straight". The conductor sets this per spawn
# (WaveSpec.drift_mode / authored hazard movement). The descent + collision response stay bespoke
# below; only the sideways wander is delegated to the shared LateralDrift pattern.
@export var drift_mode: String = "drift_all"
const LateralDrift = preload("res://scripts/enemies/patterns/lateral_drift.gd")
var _drift: Resource = null
# Soft mutual separation so rocks collide but don't MERGE (Roman 2026-06-23). Spring stiffness for
# the per-frame push (higher = firmer separation).
const HazardSpacing = preload("res://scripts/enemies/hazard_spacing.gd")
const SEP_STIFFNESS: float = 6.0

# Impact jolt (Roman 2026-06-14): halved the player kick (was 50) AND added a short
# per-player grace so a chain of asteroids can't pinball the ship energetically off one
# impact. The grace lives on the PLAYER (a meta) so ANY asteroid respects a recent kick.
const PLAYER_KICK := 25.0
const JOLT_GRACE_MS := 450

const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"

# Authored particle scenes (Roman 2026-06-15) replace the old code-driven asteroid FX:
#   • DEBRIS_TRAIL_SCENE — drifting trail parented to the live rock (was per-frame 1px motes).
#   • AsteroidExplosionFx — one-shot death burst (was the _spawn_dust cloud + mote spray).
# The procgen CHUNKS are RETAINED (_spawn_asteroid_fragments) and now sink into the wreck
# layer as they exit, instead of fading out in place.
const DEBRIS_TRAIL_SCENE := preload("res://scenes/effects/asteroid_debris_trail.tscn")
const AsteroidExplosionFx := preload("res://scripts/effects/asteroid_explosion.gd")
const WreckLayer := preload("res://scripts/effects/wreck_layer.gd")
const AsteroidFragmentScript := preload("res://scripts/effects/asteroid_fragment.gd")


func _ready() -> void:
	max_health = 5
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false  # asteroids tumble, they don't have a "front"
	has_ship_vfx = false  # no ground shadow / damage-overlay — asteroids shatter, not fray
	wants_outline = false  # asteroids carry their own procgen outline
	offscreen_mode = OffscreenMode.NONE
	# Low altitude (Roman 2026-07-18, stronghold-assault go-live): ships + bullets (z 0) FLY OVER rocks.
	# -1 keeps the rock above the ground plane (structures/stronghold bases at -5..-4) — it's airborne,
	# just lower than the combatants — and its own children (debris trail -1 rel) stay under it.
	z_index = -1
	# Descent intake (Roman 2026-07-02 speed-source pass): when the bench/director hands a move_speed,
	# drive off it (rung-scale tunable); otherwise keep the authored drift_speed. Never overrides a
	# handed value. drift_speed stays the live working var — collision slowdown mutates it below.
	if move_speed > 0.0:
		drift_speed = move_speed
	super._ready()
	# Lateral-drift pattern (shared). Mode is set by the conductor via drift_mode before add_child;
	# the home lane is captured on the first step (after start() positions us). Default "drift_all"
	# reproduces the historical free-band drift.
	_drift = LateralDrift.new()
	_drift.mode = LateralDrift.mode_from_key(drift_mode)
	add_to_group("asteroids")   # for mutual soft-separation (HazardSpacing)
	# Freespace Miner signal event (asteroid_bonus_bounty) + the Mining Contract
	# Condition (grant.asteroid_bounty) both raise per-asteroid bounty; additive so
	# they STACK (design §4f). main.gd clears the event flag at level end.
	if has_node("/root/Run"):
		var _run = get_node("/root/Run")
		bounty_value += int(_run.asteroid_bonus_bounty) + int(_run.cond_sum("grant.asteroid_bounty"))
	# Replace the placeholder Sprite2D with the procgen Asteroid scene so each
	# hazard rock has a unique generated silhouette. Existing collision shape
	# stays as the gameplay hitbox.
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	# Baked main-rock visual (flagged): swap the live procgen Asteroids.gdshader rock for a
	# Sprite2D from the shared atlas — removes the LAST live asteroid shader from an asteroid
	# POI. The Area2D hitbox/health/gameplay is untouched; only the visual swaps. Falls through
	# to the procgen rock below when the flag is off / the atlas isn't baked yet.
	if AsteroidBakeCache.enabled and AsteroidBakeCache.is_ready() and _build_baked_main_visual():
		rotation = randf_range(-0.3, 0.3)
		_attach_debris_trail()
		return
	var ps = load(PROCGEN_ASTEROID)
	if ps != null:
		var visual = ps.instantiate()
		# Duplicate the shader material so this asteroid's seed is unique.
		var inner: Node = visual.get_node_or_null("Asteroid")
		if inner and "material" in inner and inner.material != null:
			inner.material = inner.material.duplicate()
		if visual.has_method("set_seed"):
			visual.set_seed(randi() % 100000)
		# Procgen Asteroid is a Control at 100x100; size + center it on the
		# Area2D origin. Roman, 2026-05-18 followup: bumped to 44-64 (was
		# 36-56) — needs to read clearly distinct from the 16-px player.
		var visual_size: float = randf_range(44.0, 64.0)
		if visual is Control:
			visual.custom_minimum_size = Vector2(visual_size, visual_size)
			visual.size = Vector2(visual_size, visual_size)
			visual.position = Vector2(-visual_size * 0.5, -visual_size * 0.5)
			visual.pivot_offset = Vector2(visual_size * 0.5, visual_size * 0.5)
		# Recolor the rock to the POI's asteroid color so hazard targets match
		# the field/backdrop the player flew into (Roman 2026-06-02). Drive the
		# shader palette, not modulate (modulate just multiplies the blue-gray
		# default). The background rocks share this hue but the parallax layers
		# dim them — so we BRIGHTEN the base here, keeping these targets reading
		# as lit foreground objects (replaces Cody's flat warm tint).
		var base: Color = Color(0.70, 0.66, 0.60)
		if has_node("/root/Run") and get_node("/root/Run").has_meta("asteroid_base_color"):
			base = get_node("/root/Run").get_meta("asteroid_base_color")
		var mx: float = maxf(base.r, maxf(base.g, base.b))
		# Normalize less aggressively + lighten less so the rock isn't washed out
		# (Roman 2026-06-11: "weird and washed out" — was 0.95 / lightened 0.4).
		base = base * (0.82 / maxf(mx, 0.01))
		if visual.has_method("set_colors"):
			visual.set_colors(PackedColorArray([base.lightened(0.22), base, base.darkened(0.4)]))
		# Trend the silhouette rounder (Roman 2026-06-11) — per-instance, so the
		# background/parallax rocks (roundness 0) are untouched.
		if inner != null and "material" in inner and inner.material != null:
			# Hazard rocks read better as large, ROUND asteroids — bump the roundness band
			# (was a flat 0.4) so they're clearly round, not lumpy (Roman 2026-06-17).
			inner.material.set_shader_parameter("roundness", randf_range(0.6, 0.75))
			# Disable dither on the gameplay rock (Roman 2026-06-15). The dither checkerboard
			# samples RAW UV.y, so it SHIFTS with any motion — reading as "odd colours shifting
			# as they move" — and HDR-2D + the bigger 44-64px rocks made the stipple a notable
			# colour overlay. Smooth-shade them; mirrors the same fix already on the chunks
			# (asteroid_fragment.gd). Background/parallax rocks keep dither (distant + static-ish).
			inner.material.set_shader_parameter("should_dither", false)
		if visual.has_method("set_pixels"):
			visual.set_pixels(visual_size)
		add_child(visual)
		_visual = visual
		_visual_size = visual_size
		_rock_color = base   # drive the death-burst tint off the rock's own colour
		# Close-up drop shadows (Roman 2026-07-18): bind the shadow rig's NEAR band into the rock's
		# material so ships passing over cast a tight 8px shadow onto the rock face — the "flying right
		# over it" read. Same one-shot bind the stronghold base uses; no-op when no rig is in the tree.
		_bind_flyover_shadow(visual)
	# Light per-spawn rotation jitter so the asteroid field doesn't look
	# perfectly uniform.
	rotation = randf_range(-0.3, 0.3)
	# Drifting debris trail: the authored asteroid_debris_trail scene, parented to the rock
	# so its world-space particles linger behind the descending rock (Roman 2026-06-15,
	# replaces the old per-frame 1px drift motes).
	_attach_debris_trail()


var _rock_color: Color = Color(0.48, 0.46, 0.45)   # set from the procgen base colour in _ready
var _visual: Node = null                           # the procgen rock visual (hidden on explode)
var _visual_size: float = 50.0
var _trail: Node2D = null                          # attached asteroid_debris_trail scene


# Bind the NEAR shadow band (8px offset, full scale — the close flyover read) from the shared
# asteroid_shadow_rig into this rock's duplicated Asteroids.gdshader material. Mirrors
# asteroid_stronghold._apply_shadow. Procgen rocks only — the baked-atlas visual is a plain Sprite2D
# with no shader, so it can't receive mask shadows (flagged path, off in production).
func _bind_flyover_shadow(visual: Node) -> void:
	if visual == null or not is_inside_tree():
		return
	var rig: Node = get_tree().get_first_node_in_group("asteroid_shadow_rig")
	if rig == null or not rig.has_method("mask_texture") or not rig.has_method("band_strength"):
		return
	var inner: Node = visual.get_node_or_null("Asteroid")
	if inner == null or not (inner is CanvasItem) or not (inner.material is ShaderMaterial):
		return
	var mat := inner.material as ShaderMaterial
	mat.set_shader_parameter("shadow_mask", rig.mask_texture("near"))
	mat.set_shader_parameter("shadow_strength", rig.band_strength("near"))


# Baked main-rock visual: a Sprite2D reading one frame cell from the shared atlas at its
# native bucket size (1:1, no scale), tinted toward the POI asteroid colour and brightened so
# it reads as a lit foreground target. Returns false (→ procgen fallback) if no usable atlas.
func _build_baked_main_visual() -> bool:
	var desired: float = randf_range(44.0, 64.0)
	var atlas := AsteroidBakeCache.get_atlas_for_size(desired)
	var tex = atlas.get("texture")
	if tex == null:
		return false
	# POI asteroid base colour (same derivation as the procgen path below).
	var base: Color = Color(0.70, 0.66, 0.60)
	if has_node("/root/Run") and get_node("/root/Run").has_meta("asteroid_base_color"):
		base = get_node("/root/Run").get_meta("asteroid_base_color")
	var mx: float = maxf(base.r, maxf(base.g, base.b))
	base = base * (0.82 / maxf(mx, 0.01))
	_rock_color = base
	var fpx: int = int(atlas.get("frame_px", 48))
	var frames: int = maxi(int(atlas.get("frames", 1)), 1)
	var variants: int = maxi(int(atlas.get("variants", 1)), 1)
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2((randi() % frames) * fpx, (randi() % variants) * fpx, fpx, fpx)
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(base.r * 1.6, base.g * 1.6, base.b * 1.6, 1.0)
	add_child(s)
	_visual = s
	_visual_size = float(fpx)
	return true


# Instantiate the drifting debris-trail scene as a child of the rock. The scene's
# GPUParticles2D emit in world space, so the emitted particles stay put as the rock
# descends — forming a trail behind it. Drawn just behind the rock visual.
func _attach_debris_trail() -> void:
	_trail = DEBRIS_TRAIL_SCENE.instantiate()
	add_child(_trail)
	_trail.position = Vector2.ZERO
	_trail.z_index = -1
	# Tint the trail to THIS rock's colour (Roman 2026-06-15). The authored scene ships a
	# neutral grey gradient; modulate multiplies through to every emitter's particles so the
	# debris matches the rock (restores the per-rock tint the old code-driven motes had).
	_trail.modulate = _rock_color


# On death, detach the trail to the fx layer so its already-emitted particles finish their
# life in world space instead of vanishing when the rock frees; stop emitting new ones.
func _release_trail() -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var fxp: Node = _fx_parent()
	_trail.reparent(fxp, true)
	for c in _trail.get_children():
		if c is GPUParticles2D:
			(c as GPUParticles2D).emitting = false
	var t: Node = _trail
	fxp.get_tree().create_timer(4.6).timeout.connect(t.queue_free)
	_trail = null


func start(pos: Vector2) -> void:
	position = pos
	if _drift != null:
		_drift.on_start(self)   # (re)capture the home lane + reseed the wander from this position

func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()
	# Smoky/dusty puff on impact (Roman, 2026-05-16). Smaller than the
	# explosion burst.
	_spawn_dust(global_position, 10, 0.30)

func _process(delta: float) -> void:
	# Lateral wander comes from the shared LateralDrift pattern (mode-confined; ALL mode reflects off
	# the band edges with the historical damping). Descent stays bespoke so the collision slow-down
	# below still works.
	if _drift != null:
		position.x += _drift.compute_step(self, delta).x
	position.y += drift_speed * delta
	# Soft mutual spacing — push apart from overlapping rocks so the field reads as distinct bodies,
	# not a merged blob (they can still bump). Applied velocity-style so it's frame-rate independent.
	position += HazardSpacing.resolve(self, "asteroids", hazard_radius()) * SEP_STIFFNESS * delta
	if position.y > screensize.y + 40.0:
		queue_free()


# Body radius for soft separation (HazardSpacing reads this off neighbours). Half the visual size.
func hazard_radius() -> float:
	return _visual_size * 0.5

func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Release the drifting trail so its particles finish instead of popping.
	_release_trail()
	# Authored death burst (Roman 2026-06-15) — replaces the old code dust cloud + mote spray.
	# No fiery explosion: a rock shatters into dust + chunks, it doesn't ignite. Tinted to the
	# rock's own colour so the burst matches the rock that shattered.
	AsteroidExplosionFx.play(_fx_parent(), global_position, _rock_color)
	# Retain the procgen chunks, but route them into the wreck layer as they exit — the
	# fragment sinks itself once it reaches the exit zone. main.gd already creates the layer
	# at combat start; ensure() (idempotent) targets the SCENE ROOT — the node that owns the
	# "Backdrop" the layer parents above — so it resolves correctly here too.
	WreckLayer.ensure(get_tree().current_scene)
	_spawn_asteroid_fragments()
	# Remove the starting asteroid immediately — the fragments ARE the rock now.
	if _visual != null and is_instance_valid(_visual):
		_visual.visible = false
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	await get_tree().create_timer(0.5).timeout
	queue_free()


# 3-6 new procgen asteroids (same colour, NEW shapes), spinning, dispersing in a cone
# along the travel direction, inheriting the drift speed. Each fragment transitions into
# the wreck layer as it exits (see asteroid_fragment.gd).
func _spawn_asteroid_fragments() -> void:
	var parent: Node = _fx_parent()
	var vx: float = _drift.current_vx() if _drift != null else 0.0
	var travel := Vector2(vx, drift_speed)
	var base_ang: float = travel.angle() if travel.length() > 1.0 else PI * 0.5  # default: down
	var n: int = 3 + randi() % 4   # 3-6
	for i in n:
		var ang: float = base_ang + randf_range(-0.55, 0.55)   # cone around the travel vector
		var spd: float = randf_range(35.0, 105.0)
		AsteroidFragmentScript.spawn(parent, global_position, {
			"velocity": Vector2(cos(ang), sin(ang)) * spd,
			"down_speed": drift_speed,
			"spin": randf_range(-3.2, 3.2),
			"size_px": randf_range(_visual_size * 0.28, _visual_size * 0.48),
			"color": _rock_color,
			"lifetime": randf_range(1.4, 2.2),
		})


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		# Billiards: shove the player aside, asteroid drifts the opposite way.
		var to_player: Vector2 = area.global_position - global_position
		if to_player.length() < 1.0:
			to_player = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var push: Vector2 = to_player.normalized() * PLAYER_KICK
		# Tween the player away briefly (mimic a kinematic impulse) — but only if it wasn't
		# kicked very recently, so successive asteroids don't pinball it. Damage + the
		# asteroid bounce + dust still happen on every contact.
		var now: int = Time.get_ticks_msec()
		if area is Node2D and now - int(area.get_meta("last_asteroid_kick_ms", 0)) >= JOLT_GRACE_MS:
			area.set_meta("last_asteroid_kick_ms", now)
			var p2 := area as Node2D
			var tw = p2.create_tween()
			tw.tween_property(p2, "position", p2.position + push, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Asteroid bounces the other way + slows briefly.
		if _drift != null:
			_drift.nudge_lateral(-push.x * 0.4)
		drift_speed = max(drift_speed * 0.4, 15.0)
		# Dust burst at the contact point.
		_spawn_dust(global_position + to_player.normalized() * 8.0)


# Dusty particle burst. Defaults match the original "bumped into a player"
# hit; callers tune `amount`/`lifetime`/`scale_lo`/`scale_hi` for hit vs
# contact feel. (Death no longer uses this — the explosion scene owns that.)
func _spawn_dust(at: Vector2, amount: int = 18, lifetime: float = 0.45, scale_lo: float = 0.7, scale_hi: float = 1.3) -> void:
	var dust := CPUParticles2D.new()
	dust.amount = amount
	dust.lifetime = lifetime
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.local_coords = false
	dust.position = Vector2.ZERO
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 10.0
	dust.direction = Vector2(0, -1)
	dust.spread = 180.0
	dust.initial_velocity_min = 80.0
	dust.initial_velocity_max = 220.0
	dust.gravity = Vector2(0, 60)
	dust.scale_amount_min = scale_lo
	dust.scale_amount_max = scale_hi
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.85, 0.82, 0.78, 1.0),
		Color(0.55, 0.5, 0.45, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	dust.color_ramp = grad
	_fx_parent().add_child(dust)
	dust.global_position = at
	get_tree().create_timer(lifetime + 0.25).timeout.connect(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)
