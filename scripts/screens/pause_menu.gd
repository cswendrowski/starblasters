extends CanvasLayer

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

@onready var _menu_btn: Button = $Center/VBox/MenuBtn
@onready var _opts_btn: Button = $Center/VBox/OptionsBtn
@onready var _back_btn: Button = $Center/VBox/BackBtn
@onready var _dim: ColorRect = $Dim
@onready var _vbox: VBoxContainer = $Center/VBox

var _paused: bool = false
# HD scope is attached only WHILE paused — the live combat behind renders at
# native 480×270, so we can't swap content_scale permanently. On pause we grab
# the last rendered frame BEFORE the swap and show it as an opaque full-screen
# backdrop: the real (now quarter-sized, overflow-spilling) game render hides
# underneath it, the menu gets HD, and the player still sees the frozen game
# properly scaled behind a translucent dim. On resume we restore native.
var _hd_scope: HdViewportScope = null
var _shot: TextureRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Above every combat CanvasLayer (Glass=1, HUD=5, Outline=10) so no game
	# element can float over the pause backdrop; below make_modal's 95 (the
	# leave-warning) and SceneTransition's fade at 128.
	layer = 80
	# Translucent — the frozen-frame backdrop underneath is what hides the game.
	_dim.color = Color(0.02, 0.03, 0.06, 0.85)
	_vbox.custom_minimum_size = Vector2(360, 0)
	_vbox.add_theme_constant_override("separation", 14)
	for b in [_menu_btn, _opts_btn, _back_btn]:
		UiTheme.style_button(b, true)
		b.custom_minimum_size = Vector2(360, 56)
	_menu_btn.pressed.connect(_to_menu)
	_opts_btn.pressed.connect(_open_options)
	_back_btn.pressed.connect(_resume)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_paused = not _paused
	if _paused:
		_capture_backdrop()   # grab the native-rendered frame BEFORE the HD swap
	visible = _paused
	get_tree().paused = _paused
	if _paused:
		_hd_scope = HdScreen.enter(self)
	else:
		HdScreen.drop(_hd_scope)
		_hd_scope = null
		_drop_backdrop()
	if has_node("/root/Music"):
		get_node("/root/Music").set_walk_frozen(_paused)


# Freeze the window's last rendered frame (still at native content scale, so it
# looks exactly like the moment of pausing) into an opaque full-rect backdrop
# behind the dim. Physical window pixels, so any window size stretches cleanly.
func _capture_backdrop() -> void:
	_drop_backdrop()
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	_shot = TextureRect.new()
	_shot.texture = ImageTexture.create_from_image(img)
	_shot.stretch_mode = TextureRect.STRETCH_SCALE
	_shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shot)
	move_child(_shot, 0)   # behind Dim + buttons


func _drop_backdrop() -> void:
	if _shot != null and is_instance_valid(_shot):
		_shot.queue_free()
	_shot = null


func _resume() -> void:
	_toggle()


func _open_options() -> void:
	var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
	if OptionsOverlay == null:
		return
	OptionsOverlay.open(self)


func _to_menu() -> void:
	_show_menu_warning()


func _show_menu_warning() -> void:
	var m := UiTheme.make_modal(95, Vector2(560, 0))
	add_child(m.layer)
	var head := Label.new()
	head.text = "Return to Main Menu?"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(head, UiTheme.LabelKind.HEADER)
	m.vbox.add_child(head)
	var body := Label.new()
	body.text = "Leaving this level will scrap your progress in it.\nYour patrol resumes from the sector map."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	m.vbox.add_child(body)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	m.vbox.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 52)
	UiTheme.style_button(cancel, true)
	cancel.pressed.connect(func(): m.layer.queue_free())
	btn_row.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Leave"
	confirm.custom_minimum_size = Vector2(150, 52)
	UiTheme.style_button(confirm, true)
	confirm.pressed.connect(func():
		_paused = false
		get_tree().paused = false
		if has_node("/root/Music"):
			get_node("/root/Music").set_walk_frozen(false)
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	btn_row.add_child(confirm)
