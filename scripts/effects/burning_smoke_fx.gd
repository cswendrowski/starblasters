extends Node2D

# BurningSmokeFx (Roman 2026-06-11) — a streaming fiery-smoke comet built FROM the
# explosion atlas (graphics/explosion.png). A moving head leaves a segmented trail;
# each segment samples a successive explosion frame, so the HEAD is the first frame
# (bright fire) and the TAIL is the final frame (dissipating smoke) — "a trail/strip
# that samples the explosion atlas across its length" (Worklist / shader handoff).
#
#   BurningSmokeFx.spawn(parent, world_pos, velocity, {...}) -> Node2D
#
# Spawn into a container that outlives the source (the projectile/explosion convention).
# Fire segments are HDR-bright so they bloom through the combat env glow; smoke
# segments fade out toward the tail.

const EXPLOSION_STRIP := preload("res://graphics/explosion.png")
const FRAMES := 8

var velocity: Vector2 = Vector2(0, 60)   # head travel (px/s)
var segment_count: int = 14              # samples along the trail
var spacing: float = 6.0                 # PIXELS between segments along the path (arc-length)
var seg_scale: float = 0.85
var lifetime: float = 1.4                # head travels this long, then the trail dissipates
var fire_boost: float = 1.4              # HDR modulate on the leading fire frames (bloom)

var _segs: Array = []                    # Sprite2D per segment (head→tail)
var _path: PackedVector2Array = PackedVector2Array()
var _t: float = 0.0
var _emitting: bool = true
var _dead: bool = false

static var _self_script: GDScript = null


# Factory. opts keys mirror the vars (velocity, segment_count, spacing, seg_scale,
# lifetime, fire_boost).
static func spawn(parent: Node, world_pos: Vector2, vel: Vector2, opts: Dictionary = {}) -> Node2D:
	if parent == null:
		return null
	if _self_script == null:
		_self_script = load("res://scripts/effects/burning_smoke_fx.gd")
	var n = _self_script.new()  # untyped: dynamic member access below
	n.global_position = world_pos
	n.velocity = vel
	if opts.has("segment_count"): n.segment_count = int(opts["segment_count"])
	if opts.has("spacing"): n.spacing = float(opts["spacing"])
	if opts.has("seg_scale"): n.seg_scale = float(opts["seg_scale"])
	if opts.has("lifetime"): n.lifetime = float(opts["lifetime"])
	if opts.has("fire_boost"): n.fire_boost = float(opts["fire_boost"])
	parent.add_child(n)
	return n


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	segment_count = maxi(2, segment_count)
	# Build the segment sprites: index 0 = head (fire), last = tail (smoke).
	for i in segment_count:
		var s := Sprite2D.new()
		s.texture = EXPLOSION_STRIP
		s.hframes = FRAMES
		s.vframes = 1
		var frame_f: float = float(i) / float(segment_count - 1) * float(FRAMES - 1)
		s.frame = int(round(frame_f))
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Leading FIRE frames glow (HDR-bright + additive); trailing SMOKE frames
		# occlude (mix) and taper out so the tail dissipates.
		var is_fire: bool = s.frame <= 3
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if is_fire else CanvasItemMaterial.BLEND_MODE_MIX
		s.material = mat
		var tail_frac: float = float(i) / float(segment_count - 1)
		var bright: float = fire_boost if is_fire else 1.0
		var a: float = lerpf(1.0, 0.35, tail_frac)
		s.modulate = Color(bright, bright, bright, a)
		s.scale = Vector2.ONE * seg_scale
		s.rotation = randf_range(0.0, TAU)   # random spawn rotation per sprite for variation
		s.z_index = 6 - i        # head draws over the tail
		s.z_as_relative = false
		add_child(s)
		_segs.append(s)
	# Seed the path so the first frames have something to sample.
	for i in segment_count * 2:
		_path.append(global_position)
	_layout_segments()


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if _emitting:
		position += velocity * delta
		# Record the head position so the trail samples back along the real path.
		_path.append(global_position)
		# Keep enough history to cover the full trail length plus slack.
		while _path.size() > 256:
			_path.remove_at(0)
		_layout_segments()
		# Fade the whole comet as it ages so it dissipates rather than holding full
		# brightness then snapping out (Roman: "fading out as they get older").
		modulate.a = clampf(lerpf(1.0, 0.4, _t / maxf(0.01, lifetime)), 0.0, 1.0)
	if _t >= lifetime and _emitting:
		_dissipate()


# Place each segment at a consistent ARC-LENGTH distance back along the head's path
# (segment i at i*spacing px behind the head), so segments overlap into a continuous
# streak regardless of head speed — index-based sampling left speed-dependent gaps.
func _layout_segments() -> void:
	var n: int = _path.size()
	if n == 0:
		return
	if _segs.is_empty():
		return
	# Head segment rides the newest point.
	if _segs[0] != null and is_instance_valid(_segs[0]):
		_segs[0].global_position = _path[n - 1]
	var seg_i: int = 1
	var acc: float = 0.0
	var j: int = n - 1
	while seg_i < _segs.size() and j > 0:
		acc += _path[j].distance_to(_path[j - 1])
		while seg_i < _segs.size() and acc >= float(seg_i) * spacing:
			var s: Sprite2D = _segs[seg_i]
			if s != null and is_instance_valid(s):
				s.global_position = _path[j - 1]
			seg_i += 1
		j -= 1
	# Any segments past the end of the recorded path clamp to the oldest point.
	while seg_i < _segs.size():
		var sr: Sprite2D = _segs[seg_i]
		if sr != null and is_instance_valid(sr):
			sr.global_position = _path[0]
		seg_i += 1


# Stop emitting + fade the whole comet out, then free.
func _dissipate() -> void:
	_emitting = false
	_t = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_finish)


func _finish() -> void:
	if _dead:
		return
	_dead = true
	queue_free()
