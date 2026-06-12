extends Node2D

# ShipDebrisEmber (Roman 2026-06-11, iterated) — the "explosion sweetener": a hero
# chunk of a destroyed ship that tumbles out of the blast wearing the (randomized)
# battle-damage overlay shader, ON FIRE — a torch flame angled along its travel, hot
# ember sparks, and a dark damage-smoke line trail — then slowly DISINTEGRATES via the
# pixelated-burn shader, with the fire/sparks/smoke burning out JUST BEFORE the chunk
# fully dissolves. Heavier cousin of dust_fragment.gd.
#
#   ShipDebrisEmber.spawn(parent, world_pos, {...}) -> ShipDebrisEmber
#
# Spawn under a container that OUTLIVES the thing that blew up (the same fx_parent
# enemy_base uses), never under the dying enemy itself.

const DEBRIS_STRIP_TEX = preload("res://graphics/effects/debris.png")
const DEBRIS_FRAMES := 6
const DAMAGE_SHADER = preload("res://graphics/damage_noise.gdshader")
const DAMAGE_NOISE_TEX_PATH := "res://resources/noise_damage.tres"
const DAMAGE_EDGE_TEX_PATH := "res://resources/edge_distance_flat.tres"
const TORCH_SHADER = preload("res://graphics/torch_fire.gdshader")
const BurnFx = preload("res://scripts/burn_fx.gd")

# Tunables (overridable through spawn()'s opts). burn_lead = fraction of life spent
# tumbling before the burn starts; the burn itself runs `burn_time` (randomized).
var velocity: Vector2 = Vector2.ZERO
var gravity: float = 90.0
var drag: float = 0.6
var spin: float = 0.0
var piece_scale: float = 1.0
var tint: Color = Color(1, 1, 1, 1)
var burn_time: float = 1.6        # the disintegration sweep duration (randomized per piece)
var _forced_frame: int = -1

var _spr: Sprite2D = null
var _torch: ColorRect = null
var _ember: CPUParticles2D = null
var _smoke: Line2D = null
var _smoke_ages: Array = []
var _smoke_acc: float = 0.0
var _t: float = 0.0
var _tumble_lead: float = 0.22    # brief tumble before the burn begins
var _burning: bool = false
var _trails_stopped: bool = false
var _dead: bool = false

const SMOKE_SAMPLE := 0.045
const SMOKE_MAX_POINTS := 20
const SMOKE_POINT_LIFE := 0.7

static var _noise_res: Texture2D = null
static var _edge_res: Texture2D = null
static var _self_script: GDScript = null


static func spawn(parent: Node, world_pos: Vector2, opts: Dictionary = {}) -> Node2D:
	if parent == null:
		return null
	if _self_script == null:
		_self_script = load("res://scripts/effects/ship_debris_ember.gd")
	var d = _self_script.new()  # untyped: dynamic member access below
	d.global_position = world_pos
	if opts.has("velocity"): d.velocity = opts["velocity"]
	if opts.has("gravity"): d.gravity = float(opts["gravity"])
	if opts.has("drag"): d.drag = float(opts["drag"])
	if opts.has("spin"): d.spin = float(opts["spin"])
	if opts.has("piece_scale"): d.piece_scale = float(opts["piece_scale"])
	if opts.has("tint"): d.tint = opts["tint"]
	if opts.has("frame"): d._forced_frame = int(opts["frame"])
	# Burn duration randomized per piece (Roman 2026-06-11: 1.25–2.0s).
	d.burn_time = float(opts.get("burn_time", randf_range(1.25, 2.0)))
	parent.add_child(d)
	return d


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	# Hero chunk wearing the randomized battle-damage overlay (Roman: sensitivity
	# 0.25–0.8, max_strength 0.95, random seed per piece).
	_spr = Sprite2D.new()
	_spr.texture = DEBRIS_STRIP_TEX
	_spr.hframes = DEBRIS_FRAMES
	_spr.vframes = 1
	_spr.frame = _forced_frame if _forced_frame >= 0 else randi() % DEBRIS_FRAMES
	_spr.scale = Vector2.ONE * piece_scale
	_spr.rotation = randf_range(0.0, TAU)
	_spr.modulate = tint
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.material = _make_damage_material()
	add_child(_spr)

	# Torch flame (the chunk is on fire) — angled along travel each frame.
	_torch = _make_torch()
	add_child(_torch)
	# Hot ember sparks streaming off the back.
	_ember = _make_ember_trail()
	add_child(_ember)
	# Dark damage-smoke LINE trail (Roman: use the damage smoke, not a puffy orb).
	# Parented to OUR container so it renders in the right viewport (combat or a lab).
	_smoke = _make_smoke_line()
	_fx_container().add_child(_smoke)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	# Tumble + arc down with drag.
	velocity.y += gravity * delta
	velocity *= maxf(0.0, 1.0 - drag * delta)
	position += velocity * delta
	if _spr != null and is_instance_valid(_spr):
		_spr.rotation += spin * delta
	# Angle the torch flame + ember cone opposite the chunk's motion (fire trails back).
	if velocity.length() > 4.0:
		var back := -velocity.normalized()
		if _torch != null and is_instance_valid(_torch):
			# torch_fire's flame grows "up" (-Y) by default → rotate up onto `back`.
			_torch.rotation = back.angle() + PI * 0.5
		if _ember != null and is_instance_valid(_ember):
			_ember.direction = back
	# Trail the damage smoke from the live chunk position.
	_sample_smoke(delta)
	# Kick off the slow disintegration once the tumble has read.
	if not _burning and _t >= _tumble_lead:
		_begin_burn()
	# Burn out the fire/sparks/smoke JUST BEFORE the chunk fully disintegrates.
	if _burning and not _trails_stopped and _t >= _tumble_lead + burn_time * 0.82:
		_stop_trails()


func _begin_burn() -> void:
	_burning = true
	if _spr == null or not is_instance_valid(_spr):
		_finish()
		return
	var origin := Vector2(randf_range(0.2, 0.8), randf_range(0.2, 0.8))
	BurnFx.apply_burn(_spr, burn_time, Color(0, 0, 0, 0), origin)
	get_tree().create_timer(_tumble_lead + burn_time + 0.4).timeout.connect(_finish)


func _stop_trails() -> void:
	_trails_stopped = true
	if _torch != null and is_instance_valid(_torch):
		var tw := _torch.create_tween()
		tw.tween_property(_torch, "modulate:a", 0.0, 0.25)
	if _ember != null and is_instance_valid(_ember):
		_ember.emitting = false


func _finish() -> void:
	if _dead:
		return
	_dead = true
	for n in [_ember, _torch, _spr]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	# Let the smoke line dissipate on its own rather than snap out.
	if _smoke != null and is_instance_valid(_smoke):
		var line := _smoke
		_smoke = null
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.4)
		tw.tween_callback(line.queue_free)
	queue_free()


# ---- smoke line -----------------------------------------------------------

# Sample the dark damage-smoke line at the chunk position + age/drift older points.
func _sample_smoke(delta: float) -> void:
	if _smoke == null or not is_instance_valid(_smoke):
		return
	# Age + drift existing points (settle upward slightly, like the damage smoke).
	for i in _smoke_ages.size():
		_smoke_ages[i] = float(_smoke_ages[i]) + delta
	for j in _smoke.get_point_count():
		_smoke.set_point_position(j, _smoke.get_point_position(j) + Vector2(0.0, -8.0 * delta))
	while _smoke_ages.size() > 0 and float(_smoke_ages[0]) >= SMOKE_POINT_LIFE:
		_smoke.remove_point(0)
		_smoke_ages.pop_front()
	if _trails_stopped:
		return
	_smoke_acc -= delta
	if _smoke_acc > 0.0:
		return
	_smoke_acc = SMOKE_SAMPLE
	_smoke.add_point(global_position)
	_smoke_ages.append(0.0)
	while _smoke.get_point_count() > SMOKE_MAX_POINTS:
		_smoke.remove_point(0)
		_smoke_ages.pop_front()


func _make_smoke_line() -> Line2D:
	var line := Line2D.new()
	line.width = 5.0 * piece_scale
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 2.0))   # tail wide/dispersed
	wc.add_point(Vector2(1.0, 0.6))   # head tight at the chunk
	line.width_curve = wc
	# Dark damage smoke: transparent tail → mid gray → transparent at the head.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([
		Color(0.18, 0.17, 0.17, 0.0),
		Color(0.20, 0.19, 0.19, 0.55),
		Color(0.24, 0.23, 0.23, 0.0),
	])
	line.gradient = g
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 2
	line.z_as_relative = false
	return line


# ---- torch ----------------------------------------------------------------

func _make_torch() -> ColorRect:
	var sz := Vector2(16.0, 26.0) * clampf(piece_scale, 0.7, 1.6)
	var rect := ColorRect.new()
	rect.size = sz
	rect.pivot_offset = sz * 0.5
	rect.position = -sz * 0.5            # centered on the chunk origin
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 7                     # over the chunk + embers
	rect.z_as_relative = false
	var mat := ShaderMaterial.new()
	mat.shader = TORCH_SHADER
	mat.set_shader_parameter("pixelSize", 0.08)
	mat.set_shader_parameter("toColor", Color.html("894400"))
	mat.set_shader_parameter("fromColor", Color.html("f06007"))
	mat.set_shader_parameter("sparkColor", Color.html("ffa435"))
	mat.set_shader_parameter("smokeColor", Color.html("050505"))
	mat.set_shader_parameter("speed", 2.6)
	mat.set_shader_parameter("sparkSpeed", 0.5)
	mat.set_shader_parameter("aspectRatio", sz.x / sz.y)
	mat.set_shader_parameter("size", Vector2(0.3, 0.85))
	mat.set_shader_parameter("alpha", 0.95)
	mat.set_shader_parameter("timeOffset", randf_range(0.0, 1000.0))
	mat.set_shader_parameter("seedOffset", randf_range(0.0, 100.0))
	rect.material = mat
	return rect


# ---- ember + damage material ----------------------------------------------

func _make_damage_material() -> ShaderMaterial:
	if _noise_res == null and ResourceLoader.exists(DAMAGE_NOISE_TEX_PATH):
		_noise_res = load(DAMAGE_NOISE_TEX_PATH)
	if _edge_res == null and ResourceLoader.exists(DAMAGE_EDGE_TEX_PATH):
		_edge_res = load(DAMAGE_EDGE_TEX_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	if _noise_res != null:
		mat.set_shader_parameter("noise_texture", _noise_res)
	if _edge_res != null:
		mat.set_shader_parameter("edge_distance_map", _edge_res)
	mat.set_shader_parameter("noise_seed", randf_range(0.0, 64.0))
	# Roman 2026-06-11: sensitivity randomized 0.25–0.8, max_strength up at 0.95.
	mat.set_shader_parameter("sensitivity", randf_range(0.25, 0.8))
	mat.set_shader_parameter("max_strength", 0.95)
	mat.set_shader_parameter("edge_bias_strength", 0.4)
	mat.set_shader_parameter("details_opacity", 0.25)
	return mat


func _make_ember_trail() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.local_coords = false
	p.amount = 14
	p.lifetime = 0.45
	p.texture = _hot_pixel()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction = Vector2(0, 1)
	p.spread = 40.0
	p.gravity = Vector2(0, 30)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 60.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	p.z_index = 5
	p.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(1.6, 1.4, 0.9, 1.0),
		Color(1.0, 0.55, 0.05, 1.0),
		Color(0.5, 0.08, 0.0, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = g
	p.emitting = true
	return p


# The container our world-space trail/smoke parents into: our own parent (combat scene
# or a dev lab's SubViewport world), so it renders in the same viewport as the chunk.
func _fx_container() -> Node:
	var p: Node = get_parent()
	if p != null and is_instance_valid(p):
		return p
	var cs: Node = get_tree().current_scene
	return cs if cs != null else get_tree().root


static var _hot_tex: Texture2D = null
static func _hot_pixel() -> Texture2D:
	if _hot_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_hot_tex = ImageTexture.create_from_image(img)
	return _hot_tex
