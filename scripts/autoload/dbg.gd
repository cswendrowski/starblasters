extends Node

# Centralized dev/debug flags. Autoloaded as "Dbg".
# Anything gated on Dbg.is_dev is automatically off in release builds
# (because OS.is_debug_build() is false when exported via --export-release).

# True when running from the editor or in a debug export.
@onready var is_dev: bool = OS.is_debug_build()

# Individual dev shortcuts. Add new flags here as needed.
# All default to is_dev so they're off automatically in release.
@onready var boss_anywhere: bool = is_dev       # Boss nodes always clickable on sector map
@onready var god_mode: bool = false             # Player can't die (set true to test bosses)
@onready var skip_intro: bool = false           # Skip the sector intro card
@onready var start_bounty: int = 0              # Spawn with this much bounty for shop testing

func _ready() -> void:
	if is_dev:
		print("[Dbg] running in dev/editor build — dev shortcuts active")


# ---- Fullscreen mouse-offset diagnostic (toggle: F9) -------------------------
# Draws a RED crosshair at where Godot thinks the cursor is, + a live dump of the
# window / content-scale / transform values. If the crosshair sits offset from your
# real hardware cursor, that gap IS the fullscreen input-offset bug. Watch the GAP
# value grow as you alt-tab in/out (it accumulates). NOT gated on is_dev so it works
# in the exported build where the bug reproduces. (Roman 2026-06-08.)
var _fsdiag: CanvasLayer = null
var _fsdiag_label: Label = null


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_toggle_fsdiag()


func _toggle_fsdiag() -> void:
	if _fsdiag != null and is_instance_valid(_fsdiag):
		_fsdiag.queue_free()
		_fsdiag = null
		_fsdiag_label = null
		set_process(false)
		return
	_fsdiag = CanvasLayer.new()
	_fsdiag.layer = 128
	add_child(_fsdiag)
	_fsdiag_label = Label.new()
	_fsdiag_label.position = Vector2(24, 24)
	_fsdiag_label.add_theme_color_override("font_color", Color(1, 1, 0.35))
	_fsdiag_label.add_theme_font_size_override("font_size", 20)
	_fsdiag.add_child(_fsdiag_label)
	_fsdiag.add_child(_FsMarker.new())
	set_process(true)


func _process(_delta: float) -> void:
	if _fsdiag_label == null or not is_instance_valid(_fsdiag_label):
		return
	var win := get_window()
	var vp_mouse: Vector2 = get_viewport().get_mouse_position()
	var os_mouse := Vector2(DisplayServer.mouse_get_position())
	var win_pos := Vector2(DisplayServer.window_get_position())
	var os_in_win := os_mouse - win_pos
	var ft := win.get_final_transform()
	var gap := vp_mouse - (ft * os_in_win)   # 0 if Godot maps the cursor correctly
	_fsdiag_label.text = "FS DIAG (F9) — red cross = where Godot thinks the cursor is\n" \
		+ "mode=%d   win_size=%s   win_pos=%s\n" % [DisplayServer.window_get_mode(), str(DisplayServer.window_get_size()), str(win_pos)] \
		+ "content_scale_size=%s\n" % str(win.content_scale_size) \
		+ "final_transform: origin=%s  scale=(%.3f, %.3f)\n" % [str(ft.origin), ft.x.x, ft.y.y] \
		+ "vp_mouse=%s   os_in_win=%s\n" % [str(vp_mouse), str(os_in_win)] \
		+ ">> GAP = %s  (should be ~0; this is the offset, watch it grow on alt-tab)" % str(gap)


# Full-rect overlay that draws a crosshair at Godot's reported mouse position.
class _FsMarker:
	extends Control
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var m := get_viewport().get_mouse_position()
		var c := Color(1, 0.2, 0.2)
		draw_line(m - Vector2(26, 0), m + Vector2(26, 0), c, 2.0)
		draw_line(m - Vector2(0, 26), m + Vector2(0, 26), c, 2.0)
		draw_circle(m, 5.0, Color(1, 0.2, 0.2, 0.5))
