extends Control

## Asteroid Field Perf Test — measures baking cost + runtime FPS of baked vs live asteroid fields.
## BAKED field: 3-layer parallax via Sprite2D pool with baked rotation atlases.
## LIVE field: procedural Asteroid instances with per-layer parallax.
## Knobs: per-layer counts (Far/Mid/Near), variant count K (4–16), frame count N (8–24), scroll speed.
##
## Reports:
## - Bake time in milliseconds (all 3 layers)
## - Live FPS (pure procedural)
## - Baked FPS (Sprite2D pool via region_rect animation)

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const SpriteBaker = preload("res://scripts/effects/sprite_baker.gd")

const ASTEROID_SCENE = preload("res://Planets/Asteroids/Asteroid.tscn")
const SAVE_PATH := "user://tuners/asteroid_field_test.json"

const FS_TITLE := 40
const FS_BODY := 18
const FS_CAPTION := 15
const FS_MONO := 14
const RAIL_W := 320
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

# Per-layer configuration (Far, Mid, Near)
const LAYER_NAMES := ["Far", "Mid", "Near"]
const LAYER_PX := [54, 112, 190]  # Native display sizes for each layer
const LAYER_SCROLL_SPEEDS := [20.0, 35.0, 55.0]  # Per-layer parallax multipliers (base × this)

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _stage: Node2D = null
var _ui: CanvasLayer = null
var _knob_box: VBoxContainer = null
var _status_label: Label = null

var _variant_count: int = 10
var _frame_count: int = 24
var _far_count: int = 50
var _mid_count: int = 30
var _near_count: int = 20
var _scroll_speed: float = 1.0

var _baked_sprites: Array = []  # Array of {node: Sprite2D, layer: int, variant: int, phase: float}
var _live_field: Node2D = null
var _bake_time_ms: float = 0.0
var _baked_active: bool = true

var _bake_in_progress: bool = false
var _layer_atlases: Array = []  # Array of {texture, variants, frames, frame_px} for Far/Mid/Near


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_values()
	_load_saved()
	_build_playspace()
	_build_overlay()


func _init_values() -> void:
	_variant_count = 10
	_frame_count = 24
	_far_count = 50
	_mid_count = 30
	_near_count = 20
	_scroll_speed = 1.0
	_baked_active = true


func _load_saved() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var json = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if json is Dictionary:
			_variant_count = int(json.get("variant_count", _variant_count))
			_frame_count = int(json.get("frame_count", _frame_count))
			_far_count = int(json.get("far_count", _far_count))
			_mid_count = int(json.get("mid_count", _mid_count))
			_near_count = int(json.get("near_count", _near_count))
			_scroll_speed = float(json.get("scroll_speed", _scroll_speed))


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
	_preview_vp.use_hdr_2d = true
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
	_preview_vp.add_child(_stage)


# ---- Overlay UI ----

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var header := _label("ASTEROID FIELD TEST", FS_TITLE, UiTheme.COLOR_ACCENT)
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

	# Status label (top center)
	_status_label = _label("", FS_BODY, UiTheme.COLOR_TEXT)
	_status_label.position = Vector2(960, 20)
	_status_label.add_theme_font_size_override("font_size", FS_MONO)
	_ui.add_child(_status_label)

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

	# Variant count knob
	_add_knob("Variants K", 4, 16, 1, float(_variant_count), func(v):
		_variant_count = int(v)
		_on_settings_changed()
	)

	# Frame count knob
	_add_knob("Frames N", 8, 32, 1, float(_frame_count), func(v):
		_frame_count = int(v)
		_on_settings_changed()
	)

	# Far count knob
	_add_knob("Far Count", 0, 120, 5, float(_far_count), func(v):
		_far_count = int(v)
		_on_field_changed()
	)

	# Mid count knob
	_add_knob("Mid Count", 0, 80, 5, float(_mid_count), func(v):
		_mid_count = int(v)
		_on_field_changed()
	)

	# Near count knob
	_add_knob("Near Count", 0, 60, 5, float(_near_count), func(v):
		_near_count = int(v)
		_on_field_changed()
	)

	# Scroll speed knob
	_add_knob("Scroll Speed", 0.2, 3.0, 0.1, _scroll_speed, func(v):
		_scroll_speed = float(v)
	)

	_knob_box.add_child(VSeparator.new())

	# Bake + Build button
	var bake_btn := Button.new()
	bake_btn.text = "Bake + Build Field"
	bake_btn.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(bake_btn, true)
	bake_btn.add_theme_font_size_override("font_size", FS_BODY)
	bake_btn.pressed.connect(_on_bake_and_build)
	_knob_box.add_child(bake_btn)

	# Toggle Live/Baked button
	var toggle_btn := Button.new()
	toggle_btn.text = "Toggle Live/Baked"
	toggle_btn.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(toggle_btn, false)
	toggle_btn.add_theme_font_size_override("font_size", FS_BODY)
	toggle_btn.pressed.connect(_on_toggle_mode)
	_knob_box.add_child(toggle_btn)


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

	var val_lbl := _label("%.0f" % current, FS_CAPTION, UiTheme.COLOR_TEXT)
	val_lbl.add_theme_font_size_override("font_size", 14)
	slider.value_changed.connect(func(v):
		val_lbl.text = "%.0f" % v
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


# ---- Bake + Build ----

func _on_bake_and_build() -> void:
	if _bake_in_progress:
		return
	_bake_in_progress = true

	# Time the total bake for all 3 layers
	var start_tick = Time.get_ticks_msec()

	_layer_atlases.clear()

	# Bake each layer at its native display size
	for layer_idx in 3:
		var layer_px = LAYER_PX[layer_idx]
		var result = await SpriteBaker.bake_variant_atlas(
			self,
			ASTEROID_SCENE,
			func(inst, variant_idx: int):
				# Configure variant: set layout reset + draw_outline = false
				if inst is Control:
					inst.anchor_left = 0.0; inst.anchor_top = 0.0
					inst.anchor_right = 0.0; inst.anchor_bottom = 0.0
					inst.offset_left = 0.0; inst.offset_top = 0.0
					inst.offset_right = 100.0; inst.offset_bottom = 100.0
					inst.size = Vector2(100, 100)
					inst.custom_minimum_size = Vector2(100, 100)
					inst.pivot_offset = Vector2.ZERO

				# Per-variant seed
				if inst.has_method("set_seed"):
					inst.set_seed(hash(variant_idx) % 10000)

				# Natural rock color per variant — earthy hue band (rust->tan), saturation and
				# value varied + decorrelated. Set on the palette via set_colors, which the bake
				# reliably captures (modulate alone read as flat grey). No rainbow.
				if inst.has_method("set_colors"):
					var hue: float = lerp(0.03, 0.11, fmod(float(variant_idx) * 0.37 + 0.05, 1.0))
					var sat: float = lerp(0.10, 0.40, fmod(float(variant_idx) * 0.61 + 0.2, 1.0))
					var val: float = lerp(0.42, 0.62, fmod(float(variant_idx) * 0.29 + 0.6, 1.0))
					var base_col := Color.from_hsv(hue, sat, val)
					inst.set_colors(PackedColorArray([
						base_col.lightened(0.35),
						base_col,
						base_col.darkened(0.45),
					]))

				# Set layer-specific pixel size (native display size)
				if inst.has_method("set_pixels"):
					inst.set_pixels(float(layer_px))

				var inner = inst.get_node_or_null("Asteroid")
				if inner is Control:
					inner.size = Vector2(100, 100)
					inner.position = Vector2.ZERO
					# Agreed asteroid look (Asteroid Lab defaults, roundness pass 2026-06-11):
					# roundness 0.6, octaves 3, light angle 225deg, warm rock tint. Roundness drives
					# the silhouette noise frequency (size = lerp(8.0, 1.5, roundness)). Surface churn
					# (time_speed) can't be baked, so the baker freezes it to capture static rotations.
					# Roundness varies per variant in a band centered on the agreed 0.6 — a single
					# flat 0.6 makes uniform smooth blobs across a field. Size (silhouette noise
					# frequency) is derived from roundness, per the Asteroid Lab's coupling.
					var rt := fmod(float(variant_idx) * 0.618 + 0.21, 1.0)
					var rnd: float = lerp(0.40, 0.78, rt)
					if inner.material is ShaderMaterial:
						var m := inner.material as ShaderMaterial
						m.set_shader_parameter("draw_outline", false)
						m.set_shader_parameter("roundness", rnd)
						m.set_shader_parameter("size", lerp(8.0, 1.5, rnd))
						m.set_shader_parameter("octaves", 3)
						var ang := deg_to_rad(225.0)
						m.set_shader_parameter("light_origin", Vector2(0.5 + 0.45 * cos(ang), 0.5 + 0.45 * sin(ang)))
					# Brightness-only modulate (hue/saturation come from set_colors above).
					var bright: float = 0.85 + 0.20 * fmod(float(variant_idx) * 0.314 + 0.5, 1.0)
					inner.modulate = Color(bright, bright, bright, 1.0),
			_variant_count,
			layer_px,  # frame_px = native display size for this layer
			_frame_count
		)

		if result.is_empty():
			push_error("Failed to bake asteroid atlas for layer %d" % layer_idx)
			_bake_in_progress = false
			return

		_layer_atlases.append(result)

	var end_tick = Time.get_ticks_msec()
	_bake_time_ms = float(end_tick - start_tick)

	# Build both baked and live fields
	_build_baked_field()
	_build_live_field()

	_baked_active = true
	_update_field_visibility()
	_bake_in_progress = false
	_save_state()


func _build_baked_field() -> void:
	# Clean up old sprites
	for sprite_data in _baked_sprites:
		var node = sprite_data.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_baked_sprites.clear()

	if _layer_atlases.is_empty():
		return

	# Build sprite pool for each layer
	var layer_counts := [_far_count, _mid_count, _near_count]

	for layer_idx in 3:
		var atlas_data = _layer_atlases[layer_idx]
		var atlas_tex = atlas_data.get("texture")
		var frame_px = atlas_data.get("frame_px")
		var variant_count = atlas_data.get("variants")
		var frame_count = atlas_data.get("frames")

		var count = layer_counts[layer_idx]

		# Spawn `count` sprites for this layer
		for i in count:
			var sprite = Sprite2D.new()
			sprite.name = "BakedAsteroid_%d_%d" % [layer_idx, i]
			sprite.texture = atlas_tex
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, frame_px, frame_px)
			sprite.centered = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

			# Random position in viewport
			var pos = Vector2(
				randf_range(0, 480),
				randf_range(-frame_px, 270 + frame_px)
			)
			sprite.position = pos

			_stage.add_child(sprite)

			# Store sprite state
			var variant = randi() % variant_count
			var phase = randf()
			# ~50% of rocks stay static; the rest drift slowly CW or CCW (sign = direction).
			var spin := 0.0
			if randf() > 0.50:
				spin = randf_range(0.03, 0.08) * (1.0 if randf() > 0.5 else -1.0)
			_baked_sprites.append({
				"node": sprite,
				"layer": layer_idx,
				"variant": variant,
				"phase": phase,
				"spin": spin,
				"frame_px": frame_px,
				"variant_count": variant_count,
				"frame_count": frame_count
			})


func _build_live_field() -> void:
	# Clean up old field
	if _live_field != null and is_instance_valid(_live_field):
		_live_field.queue_free()
	_live_field = null

	_live_field = Node2D.new()
	_live_field.name = "LiveField"

	# Build live asteroid instances for each layer with same per-layer counts
	var layer_counts := [_far_count, _mid_count, _near_count]

	for layer_idx in 3:
		var layer_px = LAYER_PX[layer_idx]
		var count = layer_counts[layer_idx]

		for i in count:
			var ast = ASTEROID_SCENE.instantiate()

			if ast is Control:
				ast.anchor_left = 0.0; ast.anchor_top = 0.0
				ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
				ast.offset_left = 0.0; ast.offset_top = 0.0
				ast.offset_right = 100.0; ast.offset_bottom = 100.0
				ast.size = Vector2(100, 100)
				ast.custom_minimum_size = Vector2(100, 100)
				ast.pivot_offset = Vector2.ZERO

			# Per-instance material so each rock gets its own seed/shape + look (Asteroid.tscn's
			# material is a shared SubResource — without duplicating, all rocks share one seed).
			var inner_live = ast.get_node_or_null("Asteroid")
			if inner_live is Control and inner_live.material is ShaderMaterial:
				inner_live.material = inner_live.material.duplicate()

			if ast.has_method("set_seed"):
				ast.set_seed(randi())

			# Natural rock color (earthy hue band) — match the baked field's palette variety.
			if ast.has_method("set_colors"):
				var hue_l: float = randf_range(0.03, 0.11)
				var sat_l: float = randf_range(0.10, 0.40)
				var val_l: float = randf_range(0.42, 0.62)
				var base_l := Color.from_hsv(hue_l, sat_l, val_l)
				ast.set_colors(PackedColorArray([
					base_l.lightened(0.35),
					base_l,
					base_l.darkened(0.45),
				]))

			# Set layer-specific pixel size (native display size)
			if ast.has_method("set_pixels"):
				ast.set_pixels(float(layer_px))

			# Varied static orientation per rock (baked field spins instead).
			if ast.has_method("set_rotates"):
				ast.set_rotates(randf() * TAU)

			# Agreed asteroid look (Asteroid Lab defaults) — match the baked field. Live keeps
			# surface churn (time_speed) that the frozen baked strip can't preserve.
			if inner_live is Control and inner_live.material is ShaderMaterial:
				var ml := inner_live.material as ShaderMaterial
				ml.set_shader_parameter("draw_outline", false)
				# Roundness band centered on the agreed 0.6 (matches the baked field's variety).
				var rnd_live := randf_range(0.40, 0.78)
				ml.set_shader_parameter("roundness", rnd_live)
				ml.set_shader_parameter("size", lerp(8.0, 1.5, rnd_live))
				ml.set_shader_parameter("octaves", 3)
				ml.set_shader_parameter("time_speed", 0.40)
				var angl := deg_to_rad(225.0)
				ml.set_shader_parameter("light_origin", Vector2(0.5 + 0.45 * cos(angl), 0.5 + 0.45 * sin(angl)))
				var bl := randf_range(0.85, 1.05)
				inner_live.modulate = Color(bl, bl, bl, 1.0)

			var pos = Vector2(
				randf_range(0, 480),
				randf_range(-layer_px, 270 + layer_px)
			)
			ast.position = pos
			ast.scale = Vector2(layer_px / 100.0, layer_px / 100.0)

			# Store layer index in metadata for scroll logic
			ast.set_meta("layer_idx", layer_idx)
			ast.set_meta("layer_px", layer_px)

			_live_field.add_child(ast)

	_stage.add_child(_live_field)


func _on_settings_changed() -> void:
	if not _bake_in_progress:
		_bake_time_ms = 0.0
		_layer_atlases.clear()
		for sprite_data in _baked_sprites:
			var node = sprite_data.get("node")
			if node != null and is_instance_valid(node):
				node.queue_free()
		_baked_sprites.clear()
	_save_state()


func _on_field_changed() -> void:
	# Rebuild live field with new per-layer counts
	if _live_field != null and is_instance_valid(_live_field):
		_live_field.queue_free()
	_live_field = null

	if not _layer_atlases.is_empty():
		_build_live_field()

	# Rebuild baked field with new counts
	if not _layer_atlases.is_empty():
		_build_baked_field()

	_save_state()


func _on_toggle_mode() -> void:
	_baked_active = not _baked_active
	_update_field_visibility()


func _update_field_visibility() -> void:
	# Show/hide baked sprites
	for sprite_data in _baked_sprites:
		var node = sprite_data.get("node")
		if node != null and is_instance_valid(node):
			node.visible = _baked_active

	# Show/hide live field
	if _live_field != null and is_instance_valid(_live_field):
		_live_field.visible = not _baked_active


func _process(delta: float) -> void:
	# Calculate total rock count
	var total_rocks = _far_count + _mid_count + _near_count

	# Update status label
	var mode_str = "BAKED" if _baked_active else "LIVE"
	var fps = Engine.get_frames_per_second()
	var bake_str = "Bake: %.0f ms" % _bake_time_ms if _bake_time_ms > 0.0 else "Bake: --"
	_status_label.text = "%s | FPS: %d | Rocks: %d | %s" % [mode_str, fps, total_rocks, bake_str]

	# Animate and scroll baked sprites
	if _baked_active:
		var time = Time.get_ticks_msec() / 1000.0

		for sprite_data in _baked_sprites:
			var node = sprite_data.get("node")
			if node == null or not is_instance_valid(node):
				continue

			var layer = sprite_data.get("layer")
			var variant = sprite_data.get("variant")
			var phase = sprite_data.get("phase")
			var frame_px = sprite_data.get("frame_px")
			var frame_count = sprite_data.get("frame_count")

			# Frame index from time + this rock's own spin (signed: +CW / -CCW / 0 = static) + phase
			var spin = sprite_data.get("spin", 0.0)
			var cycle = fmod(time * spin + phase, 1.0)
			if cycle < 0.0:
				cycle += 1.0
			var f = int(cycle * frame_count) % frame_count

			# Update region_rect: col = frame index, row = variant
			node.region_rect = Rect2(f * frame_px, variant * frame_px, frame_px, frame_px)

			# Per-layer parallax scroll speed
			var layer_scroll_speed = LAYER_SCROLL_SPEEDS[layer] * _scroll_speed
			node.position.y += layer_scroll_speed * delta

			# Wrap around when off-screen
			var wrap_threshold = 270 + frame_px
			if node.position.y > wrap_threshold:
				node.position.y = -frame_px

	# Scroll live field with per-layer parallax
	if _live_field != null and is_instance_valid(_live_field):
		for child in _live_field.get_children():
			if child is Node2D and child.has_meta("layer_idx"):
				var layer_idx = child.get_meta("layer_idx")
				var layer_px = child.get_meta("layer_px")
				var layer_scroll_speed = LAYER_SCROLL_SPEEDS[layer_idx] * _scroll_speed

				child.position.y += layer_scroll_speed * delta

				# Wrap around when off-screen
				var wrap_threshold = 270 + layer_px
				if child.position.y > wrap_threshold:
					child.position.y = -layer_px


func _save_state() -> void:
	var data = {
		"variant_count": _variant_count,
		"frame_count": _frame_count,
		"far_count": _far_count,
		"mid_count": _mid_count,
		"near_count": _near_count,
		"scroll_speed": _scroll_speed,
	}
	var json_str = JSON.stringify(data)
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/dev_menu.tscn")
