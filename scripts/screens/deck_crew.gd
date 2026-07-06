extends Node2D

# DeckCrew — a tiny top-down deckhand that wanders a bounds rect with a drop shadow, part of the
# reusable Deck Life system (docs/deck_life_plan_2026-07-04.md). Surface-agnostic: all positions are in
# the PARENT's local space; the host (outpost plate now, ship-select stage later) hands it a walkable
# bounds rect + a slow speed. Absolute z so it draws between the deck plate and the ship.
#
# Top-down 2px square body (matches the game's top-down perspective — NOT a side-on person). WORK state
# emits a welding arc (flickering light + sparks) when dispatched with weld=true, so crew visibly work
# the ship on Repair/Upgrade. go_to()/leave() are the reaction hooks DeckLife drives.

enum St { IDLE, WANDER, WORK, LEAVE }

const BODY_Z := -5
const SHADOW_Z := -6
const WELD_Z := -3

const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")

var speed: float = 0.8          # px per 60fps frame
var pinned: bool = false        # DeckLife drives our position (e.g. carrying a crate); FSM paused
var _bounds: Rect2 = Rect2()
var _state: int = St.IDLE
var _target: Vector2 = Vector2.ZERO
var _timer: float = 0.0
var _work_after: float = 0.0    # seconds to WORK once the current WANDER target is reached (0 = none)
var _weld_next: bool = false     # the queued WORK is a weld (sparks + arc) vs a plain pause
var _bob_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _body: Sprite2D = null
var _shadow: Sprite2D = null
var _weld_light: PointLight2D = null
var _weld_sparks = null
var _weld_flick: float = 0.0


func setup(bounds: Rect2, spd: float, suit: Color, seed_v: int) -> void:
	_bounds = bounds
	speed = maxf(0.05, spd)
	_rng.seed = seed_v
	_build_visual(suit)
	position = _rand_point()
	_enter_idle(_rng.randf_range(0.0, 2.0))


func _build_visual(suit: Color) -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = _shadow_tex()
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.z_index = SHADOW_Z
	_shadow.z_as_relative = false
	_shadow.position = Vector2(0, 2)
	_shadow.modulate = Color(0, 0, 0, 0.38)
	add_child(_shadow)
	_body = Sprite2D.new()
	_body.texture = _crew_tex(suit)
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.z_index = BODY_Z
	_body.z_as_relative = false
	add_child(_body)


# Top-down 2×2 crew square (a helmet seen from above): suit color with a 1px lighter corner so it reads.
static func _crew_tex(suit: Color) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(suit)
	img.set_pixel(0, 0, suit.lightened(0.35))
	return ImageTexture.create_from_image(img)


# A 3×2 dark blob for the drop shadow (tinted + alpha'd at build).
static func _shadow_tex() -> ImageTexture:
	var img := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(2, 0, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# --- Reaction hooks (driven by DeckLife) ---

# Walk to `pos` (may be up at the ship) then WORK in place for `work_secs`. weld=true → arc + sparks.
func go_to(pos: Vector2, work_secs: float, weld: bool = false) -> void:
	_target = pos.round()
	_work_after = maxf(0.0, work_secs)
	_weld_next = weld
	_state = St.WANDER


# Clear the deck: walk to `edge` and stop (host frees us when the plate slides out).
func leave(edge: Vector2) -> void:
	_target = edge.round()
	_work_after = 0.0
	_state = St.LEAVE


# DeckLife pins us while carrying a crate: it sets our position each frame; our FSM stands down.
func set_pinned(on: bool) -> void:
	pinned = on
	_rest_bob()
	if not on:
		_end_weld()
		_enter_idle(_rng.randf_range(0.2, 1.0))


func _process(delta: float) -> void:
	if pinned:
		return
	match _state:
		St.IDLE:
			_timer -= delta
			_rest_bob()
			if _timer <= 0.0:
				_target = _rand_point()
				_state = St.WANDER
		St.WANDER:
			if _step_toward(_target, delta):
				if _work_after > 0.0:
					_state = St.WORK
					_timer = _work_after
					_work_after = 0.0
					if _weld_next:
						_begin_weld()
				else:
					_enter_idle(_rng.randf_range(0.6, 2.6))
		St.WORK:
			_timer -= delta
			_rest_bob()
			_tick_weld(delta)
			if _timer <= 0.0:
				_end_weld()
				_enter_idle(_rng.randf_range(0.4, 1.2))
		St.LEAVE:
			if _step_toward(_target, delta):
				_state = St.IDLE
				_timer = 1e9   # park at the edge


func _step_toward(t: Vector2, delta: float) -> bool:
	var to := t - position
	var d := to.length()
	if d <= speed:
		position = t
		return true
	position = (position + to / d * speed * 60.0 * delta).round()
	# Subtle 1px walk bob at half the old cadence (top-down, so keep it gentle).
	_bob_t += delta * 4.5
	_body.position.y = -1 if int(_bob_t) % 2 == 0 else 0
	return false


func _rest_bob() -> void:
	if _body != null:
		_body.position.y = 0


func _enter_idle(secs: float) -> void:
	_state = St.IDLE
	_timer = secs
	_rest_bob()


func _rand_point() -> Vector2:
	return Vector2(
		round(_rng.randf_range(_bounds.position.x, _bounds.end.x)),
		round(_rng.randf_range(_bounds.position.y, _bounds.end.y)))


# --- Welding arc (WORK + weld) --------------------------------------------

func _begin_weld() -> void:
	if _weld_light == null:
		_weld_light = PointLightFx.make(Vector2(0, -1), Color(0.72, 0.84, 1.0), 0.32, PointLightFx.make_texture(32))
		_weld_light.z_index = WELD_Z
		_weld_light.z_as_relative = false
		add_child(_weld_light)
	if _weld_sparks == null:
		_weld_sparks = SparkTrailFx.spawn(self, Vector2(0, -1))
		var p = SparkTrailFx.particles(_weld_sparks) if _weld_sparks != null else null
		if p != null:
			p.amount = 10
			p.emitting = true


func _tick_weld(_delta: float) -> void:
	if _weld_light == null or not is_instance_valid(_weld_light):
		return
	_weld_flick -= _delta
	if _weld_flick <= 0.0:
		_weld_light.energy = _rng.randf_range(0.25, 2.2)   # arc strobe
		_weld_flick = _rng.randf_range(0.03, 0.11)


func _end_weld() -> void:
	if _weld_light != null and is_instance_valid(_weld_light):
		_weld_light.queue_free()
	_weld_light = null
	if _weld_sparks != null and is_instance_valid(_weld_sparks):
		var p = SparkTrailFx.particles(_weld_sparks)
		if p != null:
			p.emitting = false
		_weld_sparks.queue_free()
	_weld_sparks = null
