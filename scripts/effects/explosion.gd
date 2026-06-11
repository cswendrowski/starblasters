extends Node2D

# Self-contained pixel-art explosion. Randomized each play so consecutive
# kills don't look identical.
#
# Visual ingredients (Roman's brief, 2026-05-16):
#   - Core explosion: full sprite strip, random rotation, light glow ramp
#   - 2-3 secondary explosions: smaller, slight delay, scattered offsets
#   - Light cast: bright modulate boost frames 0-3, fades to neutral by 6+
#   - Glow / bloom: additive-tint "halo" sprite over the first 4-5 frames
#   - Sparks + debris: GPUParticles2D radial burst on spawn
#
# Tunables on the @export are the most likely things you'd want to tweak.

# Strip + frame count are settable so variant scenes can swap the artwork (e.g.
# explosion_small_circle.tscn = the 16px / 9-frame circle). Defaults = the
# original 8-frame explosion.png so existing callers are unchanged.
@export var strip: Texture2D = preload("res://graphics/explosion.png")
@export var frames: int = 8

@export var base_scale: float = 1.0
@export var frame_duration: float = 0.07  # ~0.56s for 8 frames
@export var spark_count: int = 18
@export var debris_count: int = 8
@export var max_radius: float = 28.0  # how far secondary booms scatter
@export var emit_light: bool = true

var _frame_timer: float = 0.0
var _frame: int = 0
var _sprites: Array = []
var _halos: Array = []  # additive glow overlays (one per sprite)
var _light: Node2D = null


func _ready() -> void:
	_spawn_core()
	_spawn_secondaries()
	_spawn_sparks()
	_spawn_debris()
	if emit_light:
		_spawn_light()
	# Set initial frame on all sprites so spawn frame 0 is visible.
	_apply_frame_to_all()
	# Hard self-destruct timer. Tight enough that the final smoke frame
	# doesn't loiter on screen for seconds (Roman, 2026-05-16: "final frame
	# hangs"). Particles run inside this window and clean up with the node.
	get_tree().create_timer(0.75).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)


func _spawn_core() -> void:
	var core := _make_explosion_sprite(Vector2.ZERO, base_scale, 0.0)
	_sprites.append({"sprite": core["sprite"], "delay": 0.0, "frame": 0})
	_halos.append(core["halo"])


func _spawn_secondaries() -> void:
	# 1–3 smaller satellites, scattered.
	var count: int = 1 + (randi() % 3)
	for i in count:
		var angle: float = randf() * TAU
		var dist: float = randf_range(max_radius * 0.4, max_radius)
		var off: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		var sc: float = randf_range(0.45, 0.75) * base_scale
		var delay: float = randf_range(0.04, 0.16)
		var pack = _make_explosion_sprite(off, sc, delay)
		_sprites.append({"sprite": pack["sprite"], "delay": delay, "frame": -1})
		_halos.append(pack["halo"])


func _make_explosion_sprite(offset: Vector2, sc: float, delay: float) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = strip
	sprite.hframes = frames
	sprite.frame = 0
	sprite.position = offset
	sprite.scale = Vector2(sc, sc)
	sprite.rotation = randf() * TAU
	sprite.visible = delay <= 0.0
	add_child(sprite)
	# Additive glow halo OVER the sprite — a warm overbright tint so the first
	# few frames "punch" before fading. Kept at the SAME scale as the core
	# (Roman 2026-06-10: explosion sprites stay 1:1 pixel-accurate, never
	# upscaled) — at matched scale it's a pure additive brightness boost on the
	# exact pixels, not an enlarged blurry copy.
	var halo := Sprite2D.new()
	halo.texture = strip
	halo.hframes = frames
	halo.frame = 0
	halo.position = offset
	halo.scale = Vector2(sc, sc)
	halo.rotation = sprite.rotation
	halo.visible = delay <= 0.0
	# HDR-bright so the explosion core clears glow_hdr_threshold=1.0 and blooms
	# (Roman renderer-polish C, 2026-06-11). Was 1.6/1.4/0.9.
	halo.self_modulate = Color(2.1, 1.8, 1.1, 0.55)
	# Additive blend = brighter where it overlaps the sprite (bloom-ish).
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = mat
	add_child(halo)
	# Halo renders behind the core sprite via z_index.
	halo.z_index = -1
	return {"sprite": sprite, "halo": halo}


func _spawn_sparks() -> void:
	# CPUParticles2D instead of GPUParticles2D — avoids gl_compatibility's
	# spotty support for one_shot + the sub-emitter shader pipeline that
	# tripped us up earlier. Same look, more reliable on web export.
	var p := CPUParticles2D.new()
	p.name = "Sparks"
	p.amount = spark_count
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.texture = _build_spark_texture()
	# CPUParticles configures fields directly on the node, not via a
	# ProcessMaterial — the rest of this function fills those in.
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 360.0
	p.gravity = Vector2(0, 80)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),
		Color(1.0, 0.55, 0.15, 1.0),
		Color(0.6, 0.15, 0.05, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = grad
	add_child(p)
	return

func _spawn_sparks_unused() -> void:
	var p := GPUParticles2D.new()
	p.name = "Sparks"
	p.amount = spark_count
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.texture = _build_spark_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 6.0
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 180.0
	m.initial_velocity_max = 360.0
	m.gravity = Vector3(0, 80, 0)
	m.scale_min = 0.6
	m.scale_max = 1.2
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct = CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),
		Color(1.0, 0.55, 0.15, 1.0),
		Color(0.6, 0.15, 0.05, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	add_child(p)


func _spawn_debris() -> void:
	if debris_count <= 0:
		return
	# Same CPU-vs-GPU swap as sparks — gl_compatibility-safe.
	var p := CPUParticles2D.new()
	p.name = "Debris"
	p.amount = debris_count
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 0.8
	p.local_coords = false
	p.texture = _build_debris_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2(0, 120)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.85, 0.6, 0.35, 1.0),
		Color(0.45, 0.3, 0.15, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	p.color_ramp = grad
	add_child(p)
	return

func _spawn_debris_unused() -> void:
	var p := GPUParticles2D.new()
	p.name = "Debris"
	p.amount = debris_count
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 0.8
	p.local_coords = false
	p.texture = _build_debris_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 8.0
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 80.0
	m.initial_velocity_max = 220.0
	m.gravity = Vector3(0, 120, 0)
	m.angular_velocity_min = -540.0
	m.angular_velocity_max = 540.0
	m.scale_min = 0.7
	m.scale_max = 1.1
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.85, 0.6, 0.35, 1.0),
		Color(0.45, 0.3, 0.15, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 16
	m.color_ramp = ramp
	p.process_material = m
	add_child(p)


# Sharp 2x2 white pixel for sparks. CPUParticles2D scale_amount controls rendered size.
static func _build_spark_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# Sharp 2x2 white pixel for debris. CPUParticles2D scale_amount controls rendered size.
static func _build_debris_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _spawn_light() -> void:
	# Light cast: additive glow sprite parented to the explosion ORIGIN.
	# Sized to ~3× the primary boom. Color cycles white → yellow → orange →
	# red → out over frames 0–6. Rendered OVER the explosion sprite so it
	# enriches the artwork instead of sitting behind it. Held to ~50% alpha
	# so it adds warmth without washing out the scene.
	_light = Sprite2D.new()
	_light.texture = _build_light_texture()
	_light.position = Vector2.ZERO  # centered on the core
	# Start at half the target size on frame 0 — the "punchy flash" grows
	# to its full scale by ~frame 1.
	var s: float = base_scale * 1.5
	_light.scale = Vector2(s, s)
	_light.self_modulate = Color(1, 1, 1, 1)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = mat
	# Above the core sprite (which is at default z_index 0) so it tints
	# the explosion artwork additively.
	_light.z_index = 1
	add_child(_light)


# Soft white radial gradient — the per-frame color cycle is applied via
# `self_modulate` so this texture stays neutral.
static func _build_light_texture() -> Texture2D:
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	# Default fill_from is (0,0) — that anchors the gradient to the top-left
	# corner and renders only a quarter-circle inside the texture. Center it
	# at (0.5, 0.5) so we get a full disc.
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# Per-frame light color (frame 0 = white flash, then yellow/orange/red, gone
# by frame 6). Used by _apply_light. Index = clamp(frame, 0, FRAMES-1).
const LIGHT_COLORS: Array = [
	Color(1.0, 1.0, 1.0, 1.0),   # 0: white flash
	Color(1.0, 0.95, 0.65, 1.0), # 1: pale yellow
	Color(1.0, 0.7, 0.3, 1.0),   # 2: orange
	Color(1.0, 0.45, 0.15, 1.0), # 3: deep orange
	Color(0.95, 0.25, 0.1, 1.0), # 4: red
	Color(0.55, 0.1, 0.05, 1.0), # 5: dark red
	Color(0.2, 0.04, 0.02, 1.0), # 6: ember
	Color(0.0, 0.0, 0.0, 1.0),   # 7: gone
]


func _process(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= frame_duration:
		_frame_timer -= frame_duration
		_frame += 1
	_apply_frame_to_all()
	_apply_light()
	# Cleanup is handled by the 1.6s timer in _ready — don't depend on
	# `$Sparks.emitting` here, it doesn't flip reliably on gl_compatibility.


func _apply_frame_to_all() -> void:
	# Each sprite advances on its own delayed timeline so the secondaries are
	# offset relative to the core. Once a sprite passes the final strip frame
	# it hides — Roman's "final frame hangs on the map for several seconds"
	# was the smoke frame loitering visible until the timer freed the node.
	var time: float = _frame * frame_duration + _frame_timer
	for entry in _sprites:
		var s: Sprite2D = entry["sprite"]
		var d: float = entry["delay"]
		var local_time: float = time - d
		if local_time < 0.0:
			s.visible = false
			continue
		var local_frame: int = int(local_time / frame_duration)
		if local_frame >= frames:
			s.visible = false
			# Halo also hides
			var idx_done: int = _sprites.find(entry)
			if idx_done >= 0 and idx_done < _halos.size():
				_halos[idx_done].visible = false
			continue
		s.visible = true
		s.frame = local_frame
		var idx: int = _sprites.find(entry)
		if idx >= 0 and idx < _halos.size():
			var halo: Sprite2D = _halos[idx]
			halo.frame = local_frame
			halo.visible = true
			var glow: float = 1.0 - clamp(float(local_frame - 3) / 3.0, 0.0, 1.0)
			halo.self_modulate.a = 0.65 * glow


func _apply_light() -> void:
	if _light == null:
		return
	# Light follows the CORE explosion's frame — frame 0 = white flash,
	# walking through LIGHT_COLORS as the boom evolves. Lerp between
	# adjacent table entries so the color cycle reads smooth.
	var time: float = _frame * frame_duration + _frame_timer
	var f: float = time / frame_duration
	var idx_lo: int = clamp(int(floor(f)), 0, LIGHT_COLORS.size() - 1)
	var idx_hi: int = clamp(idx_lo + 1, 0, LIGHT_COLORS.size() - 1)
	var t: float = clamp(f - float(idx_lo), 0.0, 1.0)
	var col: Color = LIGHT_COLORS[idx_lo].lerp(LIGHT_COLORS[idx_hi], t)
	# Brief initial flash on frame 0 only.
	if f < 1.0:
		col = col.lerp(Color(1, 1, 1, 1), 1.0 - f)
	# Hold the additive light at ~50% so it warms the scene rather than
	# blowing it out. Color cycle still drives hue/value above this.
	col.a *= 0.5
	_light.self_modulate = col
	# Punch the flash: light starts half size on frame 0 and grows to its
	# full 3× over frame 0→1. After that it holds steady.
	var size_t: float = clamp(f, 0.0, 1.0)
	var size_mult: float = lerp(1.5, 3.0, size_t)
	var s: float = base_scale * size_mult
	_light.scale = Vector2(s, s)
