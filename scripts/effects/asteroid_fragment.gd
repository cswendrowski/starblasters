extends Node2D

# AsteroidFragment (Roman 2026-06-11) — a procgen asteroid chunk thrown from a
# shattered hazard asteroid. New random SHAPE (fresh seed), same colour as the parent,
# spins, disperses along its launch vector, and inherits the parent's downward drift.
#
# Wreck-layer transition (Roman 2026-06-15): the chunk no longer fades out in place as a
# stand-in. When it reaches the exit zone it SINKS INTO the real wreck layer — reparented
# (world transform preserved) so it takes the near-band colour grade, recedes a touch, and
# drifts off-screen BEHIND gameplay. Mirrors wreck_drift's exit-zone seam.
#
#   AsteroidFragment.spawn(parent, world_pos, {...}) -> Node2D

const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"
const WRECK_GROUP := "wreck_layer"
const EXIT_ZONE_Y := 195.0      # mirrors wreck_drift.EXIT_ZONE_Y (Zones.DEPARTURE_START)
const DESPAWN_Y := 320.0        # below the 270 playfield — free here
const SAFETY_LIFETIME := 10.0   # backstop free if it never reaches the exit/despawn

var velocity: Vector2 = Vector2.ZERO   # launch (cone) velocity
var down_speed: float = 60.0           # parent's drift speed — fragment leaves at the same rate
var drag: float = 1.1                  # bleed the cone velocity so the down-drift dominates
var spin: float = 0.0                  # rad/s
var size_px: float = 22.0
var color: Color = Color(0.5, 0.48, 0.46)
var lifetime: float = 1.8              # kept for spawn() compat; no longer drives a fade

var _t: float = 0.0
var _visual: Node = null
var _dead: bool = false
var _reparented: bool = false

static var _self_script: GDScript = null


static func spawn(parent: Node, world_pos: Vector2, opts: Dictionary = {}) -> Node2D:
	if parent == null:
		return null
	if _self_script == null:
		_self_script = load("res://scripts/effects/asteroid_fragment.gd")
	var f = _self_script.new()
	f.global_position = world_pos
	if opts.has("velocity"): f.velocity = opts["velocity"]
	if opts.has("down_speed"): f.down_speed = float(opts["down_speed"])
	if opts.has("spin"): f.spin = float(opts["spin"])
	if opts.has("size_px"): f.size_px = float(opts["size_px"])
	if opts.has("color"): f.color = opts["color"]
	if opts.has("lifetime"): f.lifetime = float(opts["lifetime"])
	parent.add_child(f)
	return f


func _ready() -> void:
	z_index = 5
	z_as_relative = false
	# Baked chunk path: reuse the shared asteroid atlas (the distant-layer bake) instead of
	# instantiating a fresh procgen Asteroid per chunk. The procgen spawn (x3-6 per death,
	# each a new Asteroids.gdshader material) is the death-time frame drop — and keeping the
	# shader off the chunks also helps the asteroid-POI combat-load burst. Same flag as the
	# backdrop bake (AsteroidBakeCache); falls through to procgen when off / not yet baked.
	if AsteroidBakeCache.enabled and AsteroidBakeCache.is_ready() and _build_baked_visual():
		return
	var ps = load(PROCGEN_ASTEROID)
	if ps == null:
		queue_free()
		return
	_visual = ps.instantiate()
	# Unique seed → a NEW silhouette for every chunk (Roman: "new shapes").
	var inner: Node = _visual.get_node_or_null("Asteroid")
	if inner != null and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
	if _visual.has_method("set_seed"):
		_visual.set_seed(randi() % 100000)
	if _visual is Control:
		(_visual as Control).custom_minimum_size = Vector2(size_px, size_px)
		(_visual as Control).size = Vector2(size_px, size_px)
		(_visual as Control).position = Vector2(-size_px * 0.5, -size_px * 0.5)
		(_visual as Control).pivot_offset = Vector2(size_px * 0.5, size_px * 0.5)
	if _visual.has_method("set_colors"):
		# Less lightening so chunks aren't washed out (Roman 2026-06-11).
		_visual.set_colors(PackedColorArray([color.lightened(0.2), color, color.darkened(0.38)]))
	if inner != null and "material" in inner and inner.material != null:
		inner.material.set_shader_parameter("roundness", 0.4)
		inner.material.set_shader_parameter("draw_outline", false)   # chunks: no pixel outline
		# Chunks no longer dither (Roman 2026-06-14): two overlapping dithered translucent rocks
		# moiré into odd colours. Smooth-shade them; the main hazard rocks stay opaque/unaffected.
		inner.material.set_shader_parameter("should_dither", false)
	if _visual.has_method("set_pixels"):
		_visual.set_pixels(size_px)
	add_child(_visual)


# Cheap baked chunk: a Sprite2D reading a random variant/frame cell from the shared
# asteroid atlas, scaled to size_px. No procgen scene, no per-chunk ShaderMaterial. Tinted
# toward the parent rock's colour so shattered debris reads as the rock it came from.
# Returns false (→ procgen fallback) if the atlas isn't usable.
func _build_baked_visual() -> bool:
	var atlas := AsteroidBakeCache.get_atlas_for_size(size_px)
	var tex = atlas.get("texture")
	if tex == null:
		return false
	var fpx: int = int(atlas.get("frame_px", 32))
	var frames: int = maxi(int(atlas.get("frames", 1)), 1)
	var variants: int = maxi(int(atlas.get("variants", 1)), 1)
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2((randi() % frames) * fpx, (randi() % variants) * fpx, fpx, fpx)
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Tint the neutral baked chunk to the parent rock's POI colour, brightened so debris reads
	# at roughly the rock's tone rather than dim (the atlas is mid-grey).
	s.modulate = Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 1.0)
	# 1:1 — render at the bucket's native px (scale 1.0); the chunk size snaps to the bucket.
	add_child(s)
	_visual = s
	return true


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	velocity *= maxf(0.0, 1.0 - drag * delta)
	position += (velocity + Vector2(0.0, down_speed)) * delta
	if _visual is Control:
		(_visual as Control).rotation += spin * delta
	elif _visual is Sprite2D:
		(_visual as Sprite2D).rotation += spin * delta
	# Sink into the wreck layer once the chunk reaches the exit zone: it recedes into the
	# near-band grade and drifts off-screen behind gameplay (replaces the old alpha fade).
	if not _reparented and global_position.y >= EXIT_ZONE_Y:
		_sink_into_wreck_layer()
	if _t >= SAFETY_LIFETIME or global_position.y > DESPAWN_Y:
		_dead = true
		queue_free()


# Reparent into the wreck layer, preserving the world transform. The layer's modulate
# applies the near-band colour grade; we also drop to the layer's depth and ease a small
# scale-down so the recession reads as sinking into the backdrop rather than a hard pop.
func _sink_into_wreck_layer() -> void:
	_reparented = true
	var layer: Node = get_tree().get_first_node_in_group(WRECK_GROUP)
	if layer == null or not is_instance_valid(layer):
		return   # no wreck layer (bare/dev scene) — keep drifting off-screen as-is
	# Read the wreck layer's grade (its modulate) BEFORE reparenting so we can ease INTO it
	# instead of snapping the chunk's colour at the seam.
	var w := Color.WHITE
	if layer is CanvasItem:
		w = (layer as CanvasItem).modulate
	reparent(layer, true)
	# Drop from the bright foreground z to the layer's depth (above backdrop, below ships).
	z_as_relative = true
	z_index = 0
	# Counter the wreck grade at the seam (so the chunk keeps its pre-sink colour), then ease the
	# compensation away over the sink — a smooth play→wreck colour transition, not a hard snap.
	modulate = Color(1.0 / maxf(w.r, 0.02), 1.0 / maxf(w.g, 0.02), 1.0 / maxf(w.b, 0.02), 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", scale * 0.8, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
