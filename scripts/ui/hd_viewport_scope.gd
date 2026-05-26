class_name HdViewportScope
extends Node

# RAII-style helper for scenes that render at HD (1920×1080) instead of
# the native 480×270 viewport. Drop one of these as a child of the host
# scene in _ready(); _enter_tree() stashes the current content_scale_size
# and swaps to HD, _exit_tree() restores it. The scope frees itself when
# the host scene is freed, so a missed cleanup or a crash mid-transition
# can't leave the next native-scale scene rendering at 1920×1080.
#
# Replaces five hand-rolled save/restore blocks (outpost / shipyard /
# parallax_tuner / pattern_editor_base / wave_editor) that were leak
# risks if _exit_tree didn't run cleanly.
#
# Usage:
#   func _ready() -> void:
#       HdViewportScope.attach(self)
#       # ...rest of HD setup...

const DEFAULT_HD := Vector2i(1920, 1080)

var target: Vector2i = DEFAULT_HD
var _prev: Vector2i = Vector2i.ZERO


# Attach a scope to `host`. Returns the scope node in case the caller
# wants to manually free it early (rare — normal lifecycle is "freed
# with host"). Pass `hd_size` to render at a non-default HD resolution.
static func attach(host: Node, hd_size: Vector2i = DEFAULT_HD) -> HdViewportScope:
	var s := HdViewportScope.new()
	s.target = hd_size
	host.add_child(s)
	return s


func _enter_tree() -> void:
	var w := get_window()
	if w == null:
		return
	_prev = w.content_scale_size
	w.content_scale_size = target


func _exit_tree() -> void:
	var w := get_window()
	if w == null:
		return
	# Only restore if we actually captured something. Guards against the
	# scope being free'd twice in a row (idempotent) and against
	# instantiating outside a window (defensive).
	if _prev != Vector2i.ZERO:
		w.content_scale_size = _prev
		_prev = Vector2i.ZERO
