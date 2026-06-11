extends "res://scripts/enemies/enemy_base.gd"

# Hazard asteroid. Slow drift, modest HP, no shoot, no bounty. Damages the
# player on contact but isn't actively hunting.

# 320×400 res rework — speeds halved. Roman 2026-06-02: +20% (55 → 66) for the
# denser/faster asteroid-field hazard pass.
@export var drift_speed: float = 60.0
@export var drift_x: float = 0.0
@export var damage_on_collide: int = 2

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
		base = base * (0.95 / maxf(mx, 0.01))  # normalize brightest channel for pop
		if visual.has_method("set_colors"):
			visual.set_colors(PackedColorArray([base.lightened(0.4), base, base.darkened(0.4)]))
		# Trend the silhouette rounder (Roman 2026-06-11) — per-instance, so the
		# background/parallax rocks (roundness 0) are untouched.
		if inner != null and "material" in inner and inner.material != null:
			inner.material.set_shader_parameter("roundness", 0.4)
		if visual.has_method("set_pixels"):
			visual.set_pixels(visual_size)
		add_child(visual)
		_rock_color = base   # drive the dust trail + shatter particles off the rock's own colour
	# Light per-spawn rotation jitter so the asteroid field doesn't look
	# perfectly uniform.
	rotation = randf_range(-0.3, 0.3)
	# Dust trail behind the asteroid so target rocks read distinct from
	# the parallax-layer background asteroids (Roman, 2026-05-18 hazard
	# pass). Thin Line2D, dust-tan, fades to transparent.
	_attach_dust_trail()


var _dust_line: Line2D = null
var _rock_color: Color = Color(0.48, 0.46, 0.45)   # set from the procgen base colour in _ready
var _dust_t: float = 0.0
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
	_dust_line.z_index = 4
	_dust_line.z_as_relative = false
	var p := get_tree().current_scene
	if p == null:
		p = get_tree().root
	p.add_child(_dust_line)


func _exit_tree() -> void:
	# Fade the dust line out instead of leaving a stub behind when the
	# asteroid leaves play.
	if _dust_line and is_instance_valid(_dust_line):
		var line: Line2D = _dust_line
		_dust_line = null
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.4)
		tw.tween_callback(line.queue_free)

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
	# Dust trail sampling (Roman, 2026-05-18 asteroid hazard pass).
	if _dust_line and is_instance_valid(_dust_line):
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = DUST_SAMPLE_INTERVAL
			_dust_line.add_point(global_position + Vector2(0, -12))
			while _dust_line.get_point_count() > DUST_MAX_POINTS:
				_dust_line.remove_point(0)
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
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# 1× scale; the dust burst below carries the heft for big asteroids.
	ExplosionFx.play(global_position, 1.0, false)
	# Chunky dusty death burst (Roman, 2026-05-16). Triple the count + a
	# longer lifetime so the cloud lingers, plus a chunkier scale.
	_spawn_dust(global_position, 60, 1.1, 1.2, 2.4)
	# Dusty shatter (Roman 2026-06-11): inert asteroid fragments + 1-2px rock-colour
	# motes, each trailing 1px dust. Harmless — pure spectacle.
	_spawn_shatter()
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.5)
	await get_tree().create_timer(0.55).timeout
	queue_free()

const FragmentScript = preload("res://scripts/effects/dust_fragment.gd")

# Throw out a few larger inert asteroid fragments + a spray of 1-2px rock-colour
# motes, each leaving a thin same-colour dust trail. All harmless (Roman 2026-06-11).
func _spawn_shatter() -> void:
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	for i in range(4 + randi() % 3):   # larger fragments
		var f = FragmentScript.new()
		f.color = _rock_color
		f.size_px = randf_range(3.0, 5.0)
		f.lifetime = randf_range(0.8, 1.3)
		var a1: float = randf_range(0.0, TAU)
		f.velocity = Vector2(cos(a1), sin(a1)) * randf_range(40.0, 110.0)
		parent.add_child(f)
		f.global_position = global_position
	for i in range(10 + randi() % 6):  # 1-2px motes
		var m = FragmentScript.new()
		m.color = _rock_color
		m.size_px = randf_range(1.0, 2.0)
		m.lifetime = randf_range(0.5, 0.9)
		var a2: float = randf_range(0.0, TAU)
		m.velocity = Vector2(cos(a2), sin(a2)) * randf_range(60.0, 160.0)
		parent.add_child(m)
		m.global_position = global_position


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		# Billiards: shove the player aside, asteroid drifts the opposite way.
		var to_player: Vector2 = area.global_position - global_position
		if to_player.length() < 1.0:
			to_player = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var push: Vector2 = to_player.normalized() * 50.0
		# Tween the player away briefly (mimic a kinematic impulse).
		if area is Node2D:
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
	get_tree().root.add_child(dust)
	dust.global_position = at
	get_tree().create_timer(lifetime + 0.25).timeout.connect(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)
