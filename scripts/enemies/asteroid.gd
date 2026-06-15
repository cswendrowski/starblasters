extends "res://scripts/enemies/enemy_base.gd"

# Hazard asteroid. Slow drift, modest HP, no shoot, no bounty. Damages the
# player on contact but isn't actively hunting.

# 320×400 res rework — speeds halved. Roman 2026-06-02: +20% (55 → 66) for the
# denser/faster asteroid-field hazard pass.
@export var drift_speed: float = 60.0
@export var drift_x: float = 0.0
@export var damage_on_collide: int = 2

# Impact jolt (Roman 2026-06-14): halved the player kick (was 50) AND added a short
# per-player grace so a chain of asteroids can't pinball the ship energetically off one
# impact. The grace lives on the PLAYER (a meta) so ANY asteroid respects a recent kick.
const PLAYER_KICK := 25.0
const JOLT_GRACE_MS := 450

const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"


func _ready() -> void:
	max_health = 5
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false  # asteroids tumble, they don't have a "front"
	has_ship_vfx = false  # no ground shadow / damage-overlay — asteroids shatter, not fray
	wants_outline = false  # asteroids carry their own procgen outline
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	# Freespace Miner signal event sets a per-asteroid bonus bounty for one
	# hazard run. Apply it on spawn; main.gd clears the flag at level end.
	if has_node("/root/Run"):
		var bonus: int = int(get_node("/root/Run").asteroid_bonus_bounty)
		if bonus > 0:
			bounty_value += bonus
	# Replace the placeholder Sprite2D with the procgen Asteroid scene so each
	# hazard rock has a unique generated silhouette. Existing collision shape
	# stays as the gameplay hitbox.
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
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
			inner.material.set_shader_parameter("roundness", 0.4)
		if visual.has_method("set_pixels"):
			visual.set_pixels(visual_size)
		add_child(visual)
		_visual = visual
		_visual_size = visual_size
		_rock_color = base   # drive the dust trail + shatter particles off the rock's own colour
	# Light per-spawn rotation jitter so the asteroid field doesn't look
	# perfectly uniform.
	rotation = randf_range(-0.3, 0.3)
	# Trail REMOVED (Roman 2026-06-11: "the trail is awful"). The asteroid now leaves
	# behind only persistent 1px rock-colour particles (_spawn_drift_debris in _process).


var _dust_line: Line2D = null
var _rock_color: Color = Color(0.48, 0.46, 0.45)   # set from the procgen base colour in _ready
var _visual: Node = null                           # the procgen rock visual (hidden on explode)
var _visual_size: float = 50.0
var _dust_t: float = 0.0
var _debris_t: float = 0.0
const AsteroidFragmentScript = preload("res://scripts/effects/asteroid_fragment.gd")
const DUST_SAMPLE_INTERVAL: float = 0.06
const DUST_MAX_POINTS: int = 14
const DUST_LIFETIME: float = 0.85


func _attach_dust_trail() -> void:
	# Dust trail tuned 2026-05-18: chunkier, dustier, matched to the
	# asteroid's actual rock palette (medium gray with warm-brown lean,
	# not desert tan). 3-stop gradient so head is solid puff, middle is
	# hazy, tail fades out. Width-curve tapers head→tail so it reads as
	# a billowing dust cloud, not a flat ribbon.
	_dust_line = Line2D.new()
	_dust_line.name = "AsteroidDust"
	_dust_line.width = 6.0
	# 30%-opacity dust the SAME colour as the rock (Roman 2026-06-11: the old fixed-tan
	# trail "was awful"). Head ~30% alpha, fading to transparent at the tail.
	var rc := _rock_color
	_dust_line.default_color = Color(rc.r, rc.g, rc.b, 0.30)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(rc.r, rc.g, rc.b, 0.30),
		Color(rc.r, rc.g, rc.b, 0.16),
		Color(rc.r, rc.g, rc.b, 0.0),
	])
	_dust_line.gradient = grad
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(1.0, 0.30))
	_dust_line.width_curve = width_curve
	_dust_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_dust_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_dust_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# Noise-textured so it reads as billowing smoke, not a flat ribbon (Roman 2026-06-11:
	# "a noise-based smoke trail the same colour as the asteroid").
	_dust_line.texture = _dust_noise_texture()
	_dust_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	_dust_line.z_index = 4
	_dust_line.z_as_relative = false
	_fx_parent().add_child(_dust_line)


# Cached soft noise strip for the smoke trail (feathered top/bottom, grainy).
static var _dust_noise_tex: Texture2D = null
static func _dust_noise_texture() -> Texture2D:
	if _dust_noise_tex != null and is_instance_valid(_dust_noise_tex):
		return _dust_noise_tex
	const W := 48
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A57
	for y in H:
		for x in W:
			var base: float = 0.55 + 0.45 * sin(float(x) * 0.4) * cos(float(y) * 0.7)
			var grain: float = rng.randf_range(0.55, 1.0)
			var v: float = float(y) / float(H - 1)
			var feather: float = clampf(1.0 - pow(abs(v - 0.5) * 2.0, 2.2), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(base * grain * feather, 0.0, 1.0)))
	_dust_noise_tex = ImageTexture.create_from_image(img)
	return _dust_noise_tex


# A 1px rock-colour debris mote left behind as the asteroid drifts. Persists FAR longer
# and drifts STRAIGHT (low drag, mostly-vertical) so the motes linger in a clean line
# behind the descending rock instead of a trail (Roman 2026-06-11).
func _spawn_drift_debris() -> void:
	var m = FragmentScript.new()
	m.color = _rock_color
	m.size_px = 1.0
	m.brightness_jitter = 0.25
	m.lifetime = randf_range(2.6, 3.8)          # persist far longer
	m.drag = 0.35                                # low drag → steady straight drift
	# Slow straight drift roughly opposite the rock's travel so motes linger behind it.
	m.velocity = Vector2(randf_range(-3.0, 3.0), randf_range(-14.0, -6.0))
	_fx_parent().add_child(m)
	m.global_position = global_position + Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 4.0))

func start(pos: Vector2) -> void:
	position = pos
	drift_x = randf_range(-10.0, 10.0)

func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()
	# Smoky/dusty puff on impact (Roman, 2026-05-16). Smaller than the
	# explosion burst.
	_spawn_dust(global_position, 10, 0.30)

func _process(delta: float) -> void:
	position.x += drift_x * delta
	position.y += drift_speed * delta
	# Leave behind 1px rock-colour debris as the rock drifts.
	if not _dying:
		_debris_t -= delta
		if _debris_t <= 0.0:
			_debris_t = randf_range(0.09, 0.18)
			_spawn_drift_debris()
	# Reflect horizontal drift at the playfield edges so the asteroid stays
	# in the gamespace (Roman, 2026-05-16). 0.6 multiplier dampens so it
	# doesn't ping-pong forever.
	# Reflect off the 216-px playfield band, not the full viewport, so the
	# rock stays in the player's shootable zone.
	if position.x < Playfield.X_MIN + 6.0 and drift_x < 0.0:
		position.x = Playfield.X_MIN + 6.0
		drift_x = -drift_x * 0.6
	elif position.x > Playfield.X_MAX - 6.0 and drift_x > 0.0:
		position.x = Playfield.X_MAX - 6.0
		drift_x = -drift_x * 0.6
	if position.y > screensize.y + 40.0:
		queue_free()

func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# No fiery explosion for asteroids (Roman 2026-06-11) — a rock shatters into dust +
	# chunks, it doesn't ignite. The dust burst + fragment-asteroids carry the death.
	# Chunky dusty death burst (Roman, 2026-05-16). Triple the count + a
	# longer lifetime so the cloud lingers, plus a chunkier scale.
	_spawn_dust(global_position, 60, 1.1, 1.2, 2.4)
	# Replace the starting rock with 3-6 spinning fragment-asteroids dispersing in a
	# cone along the travel direction + a spray of 1px rock-colour motes (Roman 2026-06-11).
	_spawn_asteroid_fragments()
	_spawn_debris_motes()
	# Remove the starting asteroid immediately — the fragments ARE the rock now.
	if _visual != null and is_instance_valid(_visual):
		_visual.visible = false
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	await get_tree().create_timer(0.5).timeout
	queue_free()

const FragmentScript = preload("res://scripts/effects/dust_fragment.gd")

# 3-6 new procgen asteroids (same colour, NEW shapes), spinning, dispersing in a cone
# along the travel direction, inheriting the drift speed + fading as they recede.
func _spawn_asteroid_fragments() -> void:
	var parent: Node = _fx_parent()
	var travel := Vector2(drift_x, drift_speed)
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


# A spray of 1px rock-colour motes (Roman: "all just 1px, with brightness variation/
# jitter so they look like they're moving"), each trailing a thin same-colour dust streak.
func _spawn_debris_motes() -> void:
	var parent: Node = _fx_parent()
	for i in range(14 + randi() % 8):
		var m = FragmentScript.new()
		m.color = _rock_color
		m.size_px = 1.0                              # all 1px
		m.brightness_jitter = 0.35                   # flickers so it reads as moving
		m.lifetime = randf_range(0.6, 1.1)
		var a2: float = randf_range(0.0, TAU)
		m.velocity = Vector2(cos(a2), sin(a2)) * randf_range(60.0, 170.0)
		parent.add_child(m)
		m.global_position = global_position


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
		drift_x = -push.x * 0.4
		drift_speed = max(drift_speed * 0.4, 15.0)
		# Dust burst at the contact point.
		_spawn_dust(global_position + to_player.normalized() * 8.0)


# Dusty particle burst. Defaults match the original "bumped into a player"
# hit; callers tune `amount`/`lifetime`/`scale_lo`/`scale_hi` for hit vs
# death feel.
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
