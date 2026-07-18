extends Control

## Asteroid Bake Lab — A/B comparison of live procedural asteroids vs baked rotation-strip flipbooks.
## Left: live Asteroid.tscn with shader rotation. Right: baked strip as AnimatedSprite2D flipbook.
## Knobs: frame count N (4–32), asteroid size, rotation speed; Re-roll button; Copy GDScript.
## Mirrors the sequence_lab / shader_lab skeleton (HD scope, native SubViewport stage, knobs rail).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const SpriteBaker = preload("res://scripts/effects/sprite_baker.gd")

const ASTEROID_SCENE = preload("res://Planets/Asteroids/Asteroid.tscn")
const SAVE_PATH := "user://tuners/asteroid_bake_lab.json"

const FS_TITLE := 40
const FS_BODY := 18
const FS_CAPTION := 15
const RAIL_W := 320
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)
# A/B display layout in the 480×270 stage: both rocks shown large + centered, side by side.
const DISPLAY_PX := 110.0
const LEFT_CENTER := Vector2(150.0, 140.0)
const RIGHT_CENTER := Vector2(330.0, 140.0)

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _stage: Node2D = null
var _ui: CanvasLayer = null
var _knob_box: VBoxContainer = null

var _frame_count: int = 12
var _asteroid_size: float = 20.0
var _rotation_speed: float = 1.0
var _current_seed: int = 0
var _current_colors: PackedColorArray = PackedColorArray()

var _live_asteroid: Node = null
var _baked_sprite: Sprite2D = null
var _bake_in_progress: bool = false
var _bake_rotation: float = 0.0  # Current rotation for frame cycling


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_values()
	_load_saved()
	_build_playspace()
	_build_overlay()
	_spawn_asteroids()


func _init_values() -> void:
	_frame_count = 12
	_asteroid_size = 20.0
	_rotation_speed = 1.0
	_current_seed = randi()
	# Default color ramp (blue-gray from Asteroid.tscn)
	_current_colors = PackedColorArray([
		Color(0.639216, 0.654902, 0.760784, 1.0),
		Color(0.298039, 0.407843, 0.521569, 1.0),
		Color(0.227451, 0.247059, 0.368627, 1.0),
	])


func _load_saved() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var json = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if json is Dictionary:
			_frame_count = int(json.get("frame_count", _frame_count))
			_asteroid_size = float(json.get("asteroid_size", _asteroid_size))
			_rotation_speed = float(json.get("rotation_speed", _rotation_speed))


# ---- Playspace (native 480×270 SubViewport) ----

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	HdScreen.apply_native_parity(_preview_vp)
	HdScreen.verify_native_subviewport.call_deferred(_preview_vp, "asteroid_bake_lab")
	sub_container.add_child(_preview_vp)

	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	gutter.z_index = -101
	_preview_vp.add_child(gutter)

	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	band.z_index = -100
	_preview_vp.add_child(band)

	_stage = Node2D.new()
	_stage.name = "Stage"
	# "bullet_world" sink so parent-less fx resolve into this native SubViewport, not the window corner.
	_stage.add_to_group("bullet_world")
	_preview_vp.add_child(_stage)

	# A/B labels (in the 480-stage; the 4× upscale makes the small font readable).
	var live_lbl := _label("LIVE", 14, UiTheme.COLOR_ACCENT)
	live_lbl.position = Vector2(LEFT_CENTER.x - 22, LEFT_CENTER.y - DISPLAY_PX * 0.5 - 20)
	_stage.add_child(live_lbl)
	var baked_lbl := _label("BAKED", 14, UiTheme.COLOR_ACCENT)
	baked_lbl.position = Vector2(RIGHT_CENTER.x - 30, RIGHT_CENTER.y - DISPLAY_PX * 0.5 - 20)
	_stage.add_child(baked_lbl)


# ---- Overlay UI ----

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var header := _label("ASTEROID BAKE LAB", FS_TITLE, UiTheme.COLOR_ACCENT)
	header.position = Vector2(MARGIN, 12)
	header.add_theme_constant_override("outline_size", 6)
	_ui.add_child(header)

	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(1920 - MARGIN - 120, 16)
	back.size = Vector2(120, 40)
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	_ui.add_child(back)

	# Right rail: knobs
	var ry := HEADER_H + MARGIN
	var rh := 540
	_ui.add_child(_panel(Vector2(1920 - MARGIN - RAIL_W, ry), Vector2(RAIL_W, rh)))
	var lbl := _label("Settings", FS_CAPTION, UiTheme.COLOR_FAINT)
	lbl.position = Vector2(1920 - MARGIN - RAIL_W + 14, ry + 10)
	_ui.add_child(lbl)

	_knob_box = VBoxContainer.new()
	_knob_box.position = Vector2(1920 - MARGIN - RAIL_W + 14, ry + 40)
	_knob_box.size = Vector2(RAIL_W - 28, rh - 60)
	_knob_box.add_theme_constant_override("separation", 12)
	_ui.add_child(_knob_box)

	# Frame count knob
	_add_knob("Frames", 4, 32, 1, _frame_count, func(v):
		_frame_count = int(v)
		_on_knob_changed()
	)

	# Asteroid size knob
	_add_knob("Size (px)", 8.0, 48.0, 1.0, _asteroid_size, func(v):
		_asteroid_size = float(v)
		_on_knob_changed()
	)

	# Rotation speed knob
	_add_knob("Rotation speed", 0.2, 3.0, 0.1, _rotation_speed, func(v):
		_rotation_speed = float(v)
	)

	_knob_box.add_child(VSeparator.new())

	# Re-roll button
	var reroll := Button.new()
	reroll.text = "Re-roll Seed"
	reroll.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(reroll, true)
	reroll.add_theme_font_size_override("font_size", FS_BODY)
	reroll.pressed.connect(_on_reroll)
	_knob_box.add_child(reroll)

	# Copy GDScript button
	var copy := Button.new()
	copy.text = "Copy GDScript"
	copy.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(copy, false)
	copy.add_theme_font_size_override("font_size", FS_BODY)
	copy.pressed.connect(_on_copy_gdscript)
	_knob_box.add_child(copy)


func _add_knob(label: String, min_v: float, max_v: float, step: float, current: float, cb: Callable) -> void:
	var lbl := _label(label, FS_CAPTION, UiTheme.COLOR_FAINT)
	_knob_box.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = current
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(func(v):
		cb.call(v)
	)
	_knob_box.add_child(slider)

	var val_lbl := _label("%.1f" % current, FS_CAPTION, UiTheme.COLOR_TEXT)
	val_lbl.add_theme_font_size_override("font_size", 14)
	slider.value_changed.connect(func(v):
		val_lbl.text = "%.1f" % v
	)
	_knob_box.add_child(val_lbl)


func _panel(pos: Vector2, size: Vector2) -> ColorRect:
	var p := ColorRect.new()
	p.position = pos
	p.size = size
	p.color = PANEL_BG
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_enabled_all(true)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


# ---- Spawn asteroids (left=live, right=baked) ----

func _spawn_asteroids() -> void:
	# LEFT: live asteroid
	if _live_asteroid != null and is_instance_valid(_live_asteroid):
		_live_asteroid.queue_free()
	_live_asteroid = ASTEROID_SCENE.instantiate()
	# Reset the PlanetKit Control's full-rect anchors to a clean top-left 100×100 box — otherwise
	# they collapse under the Node2D stage parent and the rock renders tiny/mispositioned. Same fix
	# layer_stellar._spawn_asteroid uses.
	if _live_asteroid is Control:
		_live_asteroid.anchor_left = 0.0; _live_asteroid.anchor_top = 0.0
		_live_asteroid.anchor_right = 0.0; _live_asteroid.anchor_bottom = 0.0
		_live_asteroid.offset_left = 0.0; _live_asteroid.offset_top = 0.0
		_live_asteroid.offset_right = 100.0; _live_asteroid.offset_bottom = 100.0
		_live_asteroid.size = Vector2(100, 100)
		_live_asteroid.custom_minimum_size = Vector2(100, 100)
		_live_asteroid.pivot_offset = Vector2.ZERO
	if _live_asteroid.has_method("set_seed"):
		_live_asteroid.set_seed(_current_seed)
	if _live_asteroid.has_method("set_colors"):
		_live_asteroid.set_colors(_current_colors)
	if _live_asteroid.has_method("set_pixels"):
		_live_asteroid.set_pixels(_asteroid_size)
	if _live_asteroid.has_method("set_rotates"):
		_live_asteroid.set_rotates(true)
	# Display large + centered (DISPLAY_PX), independent of the in-game size/pixel-res knob.
	var s := DISPLAY_PX / 100.0
	_live_asteroid.scale = Vector2(s, s)
	_live_asteroid.position = LEFT_CENTER - Vector2(DISPLAY_PX, DISPLAY_PX) * 0.5
	_stage.add_child(_live_asteroid)

	# RIGHT: start bake
	_bake_and_display_right()


func _on_knob_changed() -> void:
	if not _bake_in_progress:
		_bake_rotation = 0.0
		_bake_and_display_right()
	_save_state()


func _bake_and_display_right() -> void:
	if _bake_in_progress:
		return
	_bake_in_progress = true

	# Remove old baked sprite
	if _baked_sprite != null and is_instance_valid(_baked_sprite):
		_baked_sprite.queue_free()
	_baked_sprite = null

	# Bake with current settings
	var texture = await SpriteBaker.bake_rotation_strip(
		self,
		ASTEROID_SCENE,
		func(inst):
			# Replicate layer_stellar's asteroid layout so the rock renders 100×100 in the bake
			# viewport — PlanetKit Controls ship full-rect anchors that otherwise collapse to a
			# blank/transparent capture (= no visible baked sprite).
			if inst is Control:
				inst.anchor_left = 0.0; inst.anchor_top = 0.0
				inst.anchor_right = 0.0; inst.anchor_bottom = 0.0
				inst.offset_left = 0.0; inst.offset_top = 0.0
				inst.offset_right = 100.0; inst.offset_bottom = 100.0
				inst.size = Vector2(100, 100)
				inst.custom_minimum_size = Vector2(100, 100)
				inst.pivot_offset = Vector2.ZERO
			if inst.has_method("set_seed"):
				inst.set_seed(_current_seed)
			if inst.has_method("set_colors"):
				inst.set_colors(_current_colors)
			if inst.has_method("set_pixels"):
				inst.set_pixels(_asteroid_size)
			var inner = inst.get_node_or_null("Asteroid")
			if inner is Control:
				inner.size = Vector2(100, 100)
				inner.position = Vector2.ZERO,
		64,  # frame_px = 64
		_frame_count
	)

	if texture == null:
		push_error("Failed to bake asteroid")
		_bake_in_progress = false
		return

	# Create Sprite2D with region_enabled to cycle frames from the horizontal strip
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 64, 64)
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Match the live display size + center on the right (Sprite2D is center-positioned).
	sprite.scale = Vector2(DISPLAY_PX / 64.0, DISPLAY_PX / 64.0)
	sprite.position = RIGHT_CENTER

	_baked_sprite = sprite
	_stage.add_child(_baked_sprite)
	_bake_in_progress = false


func _process(delta: float) -> void:
	# Drive left (live) asteroid rotation via shader param
	if _live_asteroid != null and is_instance_valid(_live_asteroid):
		var inner = _live_asteroid.get_node_or_null("Asteroid")
		if inner != null and is_instance_valid(inner) and inner.material is ShaderMaterial:
			var current_rot = float((inner.material as ShaderMaterial).get_shader_parameter("rotation"))
			var new_rot = fmod(current_rot + _rotation_speed * TAU * delta, TAU)
			(inner.material as ShaderMaterial).set_shader_parameter("rotation", new_rot)

	# Drive right (baked) sprite frame cycling
	if _baked_sprite != null and is_instance_valid(_baked_sprite):
		_bake_rotation = fmod(_bake_rotation + _rotation_speed * TAU * delta, TAU)
		var frame_idx = int((_bake_rotation / TAU) * _frame_count) % _frame_count
		var frame_x = frame_idx * 64
		_baked_sprite.region_rect = Rect2(frame_x, 0, 64, 64)


func _on_reroll() -> void:
	_current_seed = randi()
	_current_colors = _tint_ramp(Color(randf_range(0.3, 1.0), randf_range(0.3, 1.0), randf_range(0.3, 1.0)))
	_bake_rotation = 0.0
	_spawn_asteroids()
	_save_state()


func _tint_ramp(base: Color) -> PackedColorArray:
	return PackedColorArray([
		base.lightened(0.35),
		base,
		base.darkened(0.45),
	])


func _on_copy_gdscript() -> void:
	var snippet = "# Asteroid Bake Lab Settings\n"
	snippet += "var frame_count: int = %d\n" % _frame_count
	snippet += "var asteroid_size: float = %.1f\n" % _asteroid_size
	snippet += "var rotation_speed: float = %.2f\n" % _rotation_speed
	DisplayServer.clipboard_set(snippet)
	print("Copied to clipboard:\n%s" % snippet)


func _save_state() -> void:
	var data = {
		"frame_count": _frame_count,
		"asteroid_size": _asteroid_size,
		"rotation_speed": _rotation_speed,
	}
	var json_str = JSON.stringify(data)
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/dev_menu.tscn")
