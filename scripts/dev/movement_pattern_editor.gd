extends "res://scripts/dev/pattern_editor_base.gd"

# Movement Pattern Editor — list/edit/save .tres movement patterns with a
# live preview that animates a dummy enemy using the current pattern.
#
# Live preview model: a Node2D ("DummyEnemy") in a SubViewport runs the
# pattern's compute_step every frame. When it exits the bottom, it
# wraps back to the spawn position. Patterns reference `enemy.position`
# (and sometimes `enemy.start_pos` for s_curve etc.) — the dummy
# provides both. The dummy isn't a real Enemy node; it's just enough
# scaffolding to drive compute_step deterministically.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")

# Preview viewport's logical dimensions — also set in the .tscn but
# read here so position math reuses the same numbers.
const PREVIEW_W := 540
const PREVIEW_H := 760
# Where the dummy spawns each loop. Mid-top of the preview viewport.
var _spawn_pos: Vector2 = Vector2(PREVIEW_W * 0.5, 60.0)
# Active pattern instance (a fresh duplicate per restart so internal
# state like timers / phases doesn't leak across iterations).
var _live_pattern: Resource = null
var _dummy: Node2D = null


func _configure() -> void:
	RESOURCE_DIR = "res://resources/patterns/movement/"
	DEFAULT_SCRIPT = StraightDown


func _ready() -> void:
	super._ready()
	_dummy = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/DummyEnemy
	# Tell the live pattern where "start" was — s_curve reads enemy.start_pos.
	if _dummy:
		_dummy.set("start_pos", _spawn_pos)
	$Body/Preview/ResetBtn.pressed.connect(_reset_preview)


# Reflection-form base calls this when a new pattern is loaded.
func _on_pattern_loaded(res: Resource) -> void:
	_restart_live_pattern(res)


# When any field on the current pattern changes, restart the preview
# from spawn so the new knob value is visible. Cheap because
# compute_step is per-frame anyway; the only cost is a re-duplicate.
func _on_field_changed(res: Resource, _prop_name: String) -> void:
	_restart_live_pattern(res)


func _restart_live_pattern(res: Resource) -> void:
	if res == null:
		_live_pattern = null
		return
	# Duplicate the in-memory resource so the pattern's internal state
	# (_t, _phase, etc.) doesn't get carried across reset.
	_live_pattern = res.duplicate()
	if _dummy:
		_dummy.position = _spawn_pos
		_dummy.set("start_pos", _spawn_pos)
	if _live_pattern.has_method("on_start") and _dummy:
		_live_pattern.on_start(_dummy)


func _reset_preview() -> void:
	_restart_live_pattern(_current_resource())


func _process(delta: float) -> void:
	if _live_pattern == null or _dummy == null:
		return
	if not _live_pattern.has_method("compute_step"):
		return
	var step: Vector2 = _live_pattern.compute_step(_dummy, delta)
	_dummy.position += step
	# Wrap when off the bottom (or sides) so the preview loops forever.
	if _dummy.position.y > PREVIEW_H + 40 \
			or _dummy.position.x < -40 \
			or _dummy.position.x > PREVIEW_W + 40:
		_restart_live_pattern(_current_resource())
