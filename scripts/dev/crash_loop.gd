extends Control
## Crash-loop launcher (Roman 2026-06-19): configure + start the automated combat-load crash test
## for the #116172 pipeline SIGSEGV. Spawns a persistent runner into the root that survives scene
## changes and reloads an asteroid POI N times. The VERDICT goes to stdout ("[crash_loop] ...") and
## user://crash_loop.log — watch those; the game DIES if the crash reproduces. Run LIVE first (the
## live asteroid shader is present, so it should still crash), then BAKED (should survive).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const RunnerScript = preload("res://scripts/dev/crash_loop_runner.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")

var _iter_spin: SpinBox = null
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	# Render at HD (1920x1080) like the other dev tools so fonts/buttons size correctly.
	_hd_scope = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(960, 0)
	v.add_theme_constant_override("separation", 20)
	center.add_child(v)

	var title := Label.new()
	title.text = "COMBAT-LOAD CRASH LOOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	v.add_child(title)

	var note := Label.new()
	note.text = "Reloads an asteroid POI N times. Verdict prints to stdout ([crash_loop] ...) and user://crash_loop.log.\nRun LIVE first (should crash), then BAKED (should survive).   Esc aborts a run."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_label(note, UiTheme.LabelKind.BODY)
	v.add_child(note)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	v.add_child(hb)
	var lbl := Label.new()
	lbl.text = "Iterations:"
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	hb.add_child(lbl)
	_iter_spin = SpinBox.new()
	_iter_spin.min_value = 1
	_iter_spin.max_value = 500
	_iter_spin.value = 50
	_iter_spin.custom_minimum_size = Vector2(180, 0)
	_iter_spin.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	hb.add_child(_iter_spin)

	v.add_child(_make_button("Run LIVE   x N", func(): _start(false)))
	v.add_child(_make_button("Run BAKED   x N", func(): _start(true)))
	v.add_child(_make_button("Back", func(): SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")))

	# Headless self-test: auto-run 2 LIVE iterations when booted headless, so the loop's mechanics
	# (spawn → mass-slay → reload) can be verified from the command line without clicking. Only
	# fires under --headless boots of THIS scene; never in the normal windowed game.
	if DisplayServer.get_name() == "headless":
		_iter_spin.value = 2
		call_deferred("_start", false)


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(b)
	b.pressed.connect(cb)
	return b


func _start(baked: bool) -> void:
	var iters := int(_iter_spin.value)
	var runner := RunnerScript.new()
	runner.name = "CrashLoopRunner"
	# Parent to the root, NOT this scene — it must survive the change_scene loop.
	get_tree().root.add_child(runner)
	runner.start(baked, iters)
