extends Node2D

# SequencePlayer — base for tunable death / wreck animation SEQUENCES, played back + tuned in the
# Sequence Lab (and droppable onto enemies later). A sequence drives a TARGET ship + its body
# SPRITE over time from a `knobs` dict (the tunable values). Subclasses:
#   • override static knob_schema() → [{key,label,min,max,step,def}] — the lab builds sliders from
#     this AND seeds the defaults from it (so the schema is the single source of truth).
#   • override _begin() — one-time setup when play() starts (capture start scale, etc.).
#   • override _on_tick(t, delta) — per-frame logic; call _finish() when the sequence completes.
#
# Lifecycle: lab calls play(target, sprite, knobs); the node ticks itself via _process; it emits
# `finished` when done (the lab loops/replays or idles). stop() halts early. The player is added as
# a SIBLING of the target in the stage (not a child) so reparenting the sprite (wreck handoff)
# doesn't disturb it.

signal finished

var target: Node2D = null      # the ship root
var sprite: Sprite2D = null    # its body sprite
var knobs: Dictionary = {}
var _t: float = 0.0
var _playing: bool = false


# Subclasses override — the tunable knob schema. Also the source of the lab's default values.
static func knob_schema() -> Array:
	return []


func play(p_target: Node2D, p_sprite: Sprite2D, p_knobs: Dictionary) -> void:
	target = p_target
	sprite = p_sprite
	knobs = p_knobs.duplicate(true)
	_t = 0.0
	_playing = true
	_begin()


func stop() -> void:
	_playing = false


# Read a knob with a fallback (so a sequence is robust if the lab omits a key).
func k(key: String, fallback: float = 0.0) -> float:
	return float(knobs.get(key, fallback))


# --- subclass hooks -------------------------------------------------------
func _begin() -> void:
	pass


func _on_tick(_elapsed: float, _delta: float) -> void:
	pass


# Called when a subclass wants the sequence to wrap up. Subclasses can override to do
# end-of-sequence work, but should call super() to emit `finished`.
func _finish() -> void:
	if not _playing:
		return
	_playing = false
	finished.emit()


func _process(delta: float) -> void:
	if not _playing:
		return
	if target == null or not is_instance_valid(target):
		_finish()
		return
	_t += delta
	_on_tick(_t, delta)
