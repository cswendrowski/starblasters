extends "res://scripts/dev/pattern_editor_base.gd"

# Shoot Pattern Editor — list/edit/save .tres shoot patterns with a live
# preview that emits visual tracers in the pattern's fire direction(s)
# every preview_interval seconds.
#
# Why a tracer model instead of real bullets: shoot_pattern.gd's
# _spawn_bullet hard-codes `enemy.get_tree().root.add_child(b)`, so any
# real bullet would spawn into the main scene tree, not our preview
# SubViewport — invisible here. Tracers are cheap Node2D markers we
# parent under our SubViewport directly.

const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")

const PREVIEW_W := 540
const PREVIEW_H := 760
const TRACER_SPEED := 320.0  # px/s
const TRACER_LIFETIME := 2.5  # seconds — long enough to traverse the preview

var _dummy_enemy: Node2D = null
var _dummy_player: Node2D = null
var _shots_layer: Node2D = null
var _interval_spin: SpinBox = null

# Local fire clock. Each tick we sample fire direction(s) by replicating
# the pattern's logic (single/aimed/spread/burst) — see _compute_fire_dirs.
var _fire_timer: float = 0.0
var _preview_interval: float = 1.0


func _configure() -> void:
	RESOURCE_DIR = "res://resources/patterns/shoot/"
	DEFAULT_SCRIPT = SingleShot


func _ready() -> void:
	super._ready()
	_dummy_enemy = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/DummyEnemy
	_dummy_player = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/DummyPlayer
	_shots_layer = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/ShotsLayer
	_interval_spin = $Body/Center/IntervalRow/IntervalSpin
	_preview_interval = _interval_spin.value
	_interval_spin.value_changed.connect(func(v: float):
		_preview_interval = v
		_fire_timer = 0.0
	)


func _on_pattern_loaded(res: Resource) -> void:
	_fire_timer = 0.0
	_clear_shots()
	_seed_preview_interval(res)


func _on_field_changed(res: Resource, prop_name: String) -> void:
	# When the designer tweaks fire_interval_min/max, reseat the preview
	# interval so the rhythm change shows up immediately.
	if prop_name == "fire_interval_min" or prop_name == "fire_interval_max":
		_seed_preview_interval(res)


# Pick the preview interval from the pattern's own fire_interval_min/max
# when both are set (positive). Falls back to the SpinBox's value when
# the pattern hasn't claimed its own rhythm. Randomise within the range
# each cycle so the visualisation matches in-game cadence variance.
func _seed_preview_interval(res: Resource) -> void:
	if res == null:
		return
	var mn := -1.0
	var mx := -1.0
	if "fire_interval_min" in res:
		mn = float(res.get("fire_interval_min"))
	if "fire_interval_max" in res:
		mx = float(res.get("fire_interval_max"))
	if mn > 0.0 and mx > 0.0:
		_preview_interval = randf_range(mn, mx)


func _clear_shots() -> void:
	if _shots_layer == null:
		return
	for child in _shots_layer.get_children():
		child.queue_free()


func _process(delta: float) -> void:
	if _shots_layer == null:
		return
	# Advance fire clock; emit tracers when interval elapses, then
	# re-roll the interval (matches in-game randf_range cadence).
	_fire_timer += delta
	if _fire_timer >= _preview_interval:
		_fire_timer = 0.0
		_emit_tracers()
		_seed_preview_interval(_current_resource())
	# Move existing tracers forward; cull when expired.
	for tr in _shots_layer.get_children():
		var dir: Vector2 = tr.get_meta("dir", Vector2(0, 1))
		var life: float = tr.get_meta("life", 0.0) + delta
		tr.position += dir * TRACER_SPEED * delta
		tr.set_meta("life", life)
		if life > TRACER_LIFETIME \
				or tr.position.y > PREVIEW_H + 40 \
				or tr.position.y < -40 \
				or tr.position.x < -40 \
				or tr.position.x > PREVIEW_W + 40:
			tr.queue_free()


# Look at the current pattern and emit one tracer per direction. We
# replicate the pattern's shape rather than calling fire() because
# fire() routes through _spawn_bullet which targets the SceneTree root.
func _emit_tracers() -> void:
	var res := _current_resource()
	if res == null or _dummy_enemy == null:
		return
	var dirs := _compute_fire_dirs(res)
	for d in dirs:
		_spawn_tracer(_dummy_enemy.position, d)


# Per-pattern fire-direction inference. Identified by script path so we
# stay reflection-based: any new shoot_pattern script that follows the
# established shape (single/aimed/spread) gets reasonable visualisation.
# Unknown scripts emit one straight-down tracer as a generic fallback.
func _compute_fire_dirs(res: Resource) -> Array:
	var script_path := ""
	if res.get_script():
		script_path = res.get_script().resource_path
	if script_path.ends_with("/single_shot.gd"):
		return [Vector2(0, 1)]
	if script_path.ends_with("/aimed_fire.gd"):
		if _dummy_player == null:
			return [Vector2(0, 1)]
		var to_p: Vector2 = _dummy_player.position - _dummy_enemy.position
		if to_p.length_squared() <= 0.001:
			return [Vector2(0, 1)]
		return [to_p.normalized()]
	if script_path.ends_with("/spread_shot.gd"):
		var count: int = int(res.get("bullet_count"))
		var spread_deg: float = float(res.get("spread_degrees"))
		if count <= 0:
			return []
		var spread_rad := deg_to_rad(spread_deg)
		var dirs: Array = []
		var step: float = 0.0
		var start: float = 0.0
		if count > 1:
			step = spread_rad / float(count - 1)
			start = -spread_rad * 0.5
		for i in range(count):
			var angle: float = start + step * float(i)
			dirs.append(Vector2(sin(angle), cos(angle)))
		return dirs
	# Generic fallback for unknown / future shoot scripts.
	return [Vector2(0, 1)]


func _spawn_tracer(at: Vector2, dir: Vector2) -> void:
	var tr := ColorRect.new()
	tr.size = Vector2(4, 10)
	tr.position = at - tr.size * 0.5
	tr.color = Color(1, 0.85, 0.3, 1)
	tr.set_meta("dir", dir)
	tr.set_meta("life", 0.0)
	_shots_layer.add_child(tr)
