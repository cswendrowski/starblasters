extends ParallaxLayerBase

const STAR_COLORS := [
	Color(0.95, 0.97, 1.00),  # cool white
	Color(1.00, 0.97, 0.92),  # warm white
	Color(1.00, 0.85, 0.60),  # orange dwarf
	Color(0.75, 0.85, 1.00),  # blue
	Color(1.00, 0.95, 0.80),  # yellow
	Color(0.95, 0.70, 0.70),  # red giant
	Color(0.80, 0.95, 0.95),  # cyan
]

const TILE_W := 480
const TILE_H := 270

# Star counts
@export var pinprick_count_min: int = 140
@export var pinprick_count_max: int = 320
@export var pop_count_min: int = 20
@export var pop_count_max: int = 70

# Scroll rates (independent — stars move nearly-static)
const FAR_RATE  := 0.02
const NEAR_RATE := 0.08

var _rng: RandomNumberGenerator = null
var _seed: int = 12345

# Twinkle entries: {rect: ColorRect, base_color: Color, phase: float, amp: float, hz: float}
var _twinkle_stars: Array = []

# Scroll accumulation for the two Parallax2D layers
var _scroll_accum_far: float  = 0.0
var _scroll_accum_near: float = 0.0

var _far_para: Node = null
var _near_para: Node = null

var _time: float = 0.0


func _ready() -> void:
	super._ready()
	_far_para  = get_node_or_null("FarStars")
	_near_para = get_node_or_null("NearStars")
	_rng = RandomNumberGenerator.new()
	_rng.seed = abs(_seed)
	_spawn_stars()


func _spawn_stars() -> void:
	# Clear existing stars
	if _far_para:
		for c in _far_para.get_children():
			c.queue_free()
	if _near_para:
		for c in _near_para.get_children():
			c.queue_free()
	_twinkle_stars.clear()

	if _far_para == null or _near_para == null:
		return

	# Pinpricks (1×1) — far layer
	var n_pinpricks := _rng.randi_range(pinprick_count_min, pinprick_count_max)
	for _i in n_pinpricks:
		var base_color: Color = STAR_COLORS[_rng.randi() % STAR_COLORS.size()]
		var brightness: float = 0.55 + _rng.randf() * 0.45
		var color := Color(base_color.r * brightness, base_color.g * brightness, base_color.b * brightness)
		var r := _make_star_rect(_rng, 1, color, _far_para)
		if _rng.randf() > 0.7:  # 30% twinkle
			_twinkle_stars.append({
				"rect": r,
				"base_color": color,
				"phase": _rng.randf() * TAU,
				"amp": _rng.randf_range(0.15, 0.45),
				"hz": _rng.randf_range(0.4, 2.2),
			})

	# Pops (2×2) — near layer for depth separation
	var n_pops := _rng.randi_range(pop_count_min, pop_count_max)
	for _i in n_pops:
		var base_color: Color = STAR_COLORS[_rng.randi() % STAR_COLORS.size()]
		var r := _make_star_rect(_rng, 2, base_color, _near_para)
		if _rng.randf() > 0.7:
			_twinkle_stars.append({
				"rect": r,
				"base_color": base_color,
				"phase": _rng.randf() * TAU,
				"amp": _rng.randf_range(0.15, 0.35),
				"hz": _rng.randf_range(0.4, 1.5),
			})


func _make_star_rect(rng: RandomNumberGenerator, size: int, color: Color, parent: Node) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(size, size)
	r.position = Vector2(
		rng.randi() % (TILE_W - size),
		rng.randi() % (TILE_H - size)
	)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _process(delta: float) -> void:
	_time += delta
	# Twinkle
	for entry in _twinkle_stars:
		if not is_instance_valid(entry.rect):
			continue
		var base: Color = entry.base_color
		var brightness: float = 1.0 - entry.amp * (0.5 - 0.5 * cos(entry.phase + _time * TAU * entry.hz))
		(entry.rect as ColorRect).color = Color(base.r * brightness, base.g * brightness, base.b * brightness)


func scroll_stars(drift_delta: float) -> void:
	_scroll_accum_far  += drift_delta * FAR_RATE
	_scroll_accum_near += drift_delta * NEAR_RATE
	if _far_para != null:
		_far_para.scroll_offset = Vector2(0, _scroll_accum_far)
	if _near_para != null:
		_near_para.scroll_offset = Vector2(0, _scroll_accum_near)


func _on_reset() -> void:
	_scroll_accum_far  = 0.0
	_scroll_accum_near = 0.0
	_time = 0.0
	if _far_para != null:
		_far_para.scroll_offset = Vector2.ZERO
	if _near_para != null:
		_near_para.scroll_offset = Vector2.ZERO
	_spawn_stars()


func reseed(new_seed: int) -> void:
	_seed = new_seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = abs(_seed)
	_spawn_stars()
