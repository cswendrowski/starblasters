extends Node2D

const FONT            = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const STAR_SCENE      = preload("res://Planets/Star/Star.tscn")

const CELL  := 16
const COLS  := 30
const ROWS  := 16

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const GRID_MINOR  := Color(0.22, 0.27, 0.35, 0.55)
const GRID_MAJOR  := Color(0.35, 0.43, 0.58, 0.85)
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)
const FONT_SIZE   := 5

# Each row: [center_px, center_py, display_px, seed, glow_color, glow_alpha, pulse_hz, pulse_phase]
# Seed parity: odd = cool blue-white (B-type), even = warm yellow-orange (G/M-type).
const STAR_DATA := [
	# B-type — cool blue-white — (64, 64)
	[64.0, 64.0,  64.0, 7,
		Color(0.45, 0.65, 1.00, 1.0), 0.65, 0.38, 0.00],
	# G-type — warm yellow — (64, 128)
	[64.0, 128.0, 32.0, 42,
		Color(1.00, 0.72, 0.18, 1.0), 0.60, 0.52, 1.10],
	# M-type — warm orange-red — (64, 192)
	[64.0, 192.0, 20.0, 16,
		Color(1.00, 0.26, 0.07, 1.0), 0.55, 0.44, 2.30],
]

var _time: float = 0.0
var _star_glows: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_stars()


func _process(delta: float) -> void:
	_time += delta
	# Stars animate via their own Planet._process — only the glow halo needs
	# manual animation here.
	for i in _star_glows.size():
		var d: Array    = STAR_DATA[i]
		var hz:         float = d[6]
		var phase:      float = d[7]
		var base_alpha: float = d[5]
		var display_px: float = d[2]
		var pulse: float = sin(_time * hz * TAU + phase)
		var glow_spr: Sprite2D = _star_glows[i].get_child(0)
		var s: float = (display_px * 2.2) / 64.0 * (1.0 + 0.06 * pulse)
		glow_spr.scale     = Vector2(s, s)
		glow_spr.modulate.a = base_alpha + 0.15 * pulse


func _build_stars() -> void:
	for d in STAR_DATA:
		var cx:         float = d[0]
		var cy:         float = d[1]
		var display_px: float = d[2]
		var seed_val:   int   = d[3]
		var glow_color: Color = d[4]
		var cool: bool        = (seed_val % 2 == 1)

		# ---- PixelPlanets Star -------------------------------------------------
		# Follow the same setup order as galaxy_backdrop._spawn_planet:
		# configure the Control, call set_pixels + set_seed BEFORE add_child
		# so the shader parameters are consistent when _ready() fires.
		var star = STAR_SCENE.instantiate()
		var sf: float = display_px / 100.0
		if star is Control:
			star.anchor_left   = 0.0;  star.anchor_top    = 0.0
			star.anchor_right  = 0.0;  star.anchor_bottom = 0.0
			star.offset_right  = 100.0; star.offset_bottom = 100.0
			star.size = Vector2(100.0, 100.0)
			star.custom_minimum_size = Vector2(100.0, 100.0)
			star.pivot_offset = Vector2.ZERO
		star.scale    = Vector2(sf, sf)
		star.position = Vector2(cx - 50.0 * sf, cy - 50.0 * sf)
		# 1:1 pixel parity — shader cells = display pixels (pixel_density=1).
		if star.has_method("set_pixels"):
			star.set_pixels(display_px)
		if star.has_method("set_seed"):
			star.set_seed(seed_val)
		if star.has_method("set_rotates"):
			star.set_rotates(false)
		add_child(star)
		# Reset ColorRect canonical sizes AFTER add_child so the nodes exist.
		_reset_star_colorrects(star)
		# Apply stellar type colors. Duplicate materials first so three stars
		# on the same preloaded scene don't share ShaderMaterial instances.
		_apply_star_colors(star, cool)

		# ---- Additive glow halo on top -----------------------------------------
		var glow_node := Node2D.new()
		glow_node.position = Vector2(cx, cy)
		add_child(glow_node)
		_star_glows.append(glow_node)

		var glow_spr := Sprite2D.new()
		var g := Gradient.new()
		g.colors  = PackedColorArray([glow_color, Color(glow_color.r, glow_color.g, glow_color.b, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient  = g
		gt.width     = 64; gt.height = 64
		gt.fill      = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to   = Vector2(1.0, 0.5)
		glow_spr.texture = gt
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow_spr.material = mat
		glow_node.add_child(glow_spr)

	_process(0.0)


# Shader colors per stellar type.
# Blobs: vec4[1], Star: vec4[4], StarFlares: vec4[2] — counts must match shaders.
func _apply_star_colors(root: Node, cool: bool) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			# Duplicate so multiple stars don't share the same material instance.
			child.material = (child.material as ShaderMaterial).duplicate()
			var mat: ShaderMaterial = child.material
			match String(child.name):
				"Star":
					mat.set_shader_parameter("colors",
						PackedColorArray([          # cool: blue-white
							Color(0.96, 1.00, 0.91, 1), Color(0.47, 0.84, 0.76, 1),
							Color(0.11, 0.57, 0.65, 1), Color(0.01, 0.24, 0.37, 1),
						]) if cool else
						PackedColorArray([          # warm: yellow-orange-red
							Color(0.96, 1.00, 0.91, 1), Color(1.00, 0.85, 0.20, 1),
							Color(1.00, 0.51, 0.23, 1), Color(0.49, 0.10, 0.10, 1),
						]))
				"Blobs":
					mat.set_shader_parameter("colors",
						PackedColorArray([Color(0.47, 0.84, 0.76, 1)]) if cool else
						PackedColorArray([Color(1.00, 0.85, 0.20, 1)]))
				"StarFlares":
					mat.set_shader_parameter("colors",
						PackedColorArray([           # cool flares
							Color(0.47, 0.84, 0.76, 1), Color(0.96, 1.00, 0.91, 1),
						]) if cool else
						PackedColorArray([           # warm flares
							Color(1.00, 0.85, 0.20, 1), Color(0.96, 1.00, 0.91, 1),
						]))
		_apply_star_colors(child, cool)


func _reset_star_colorrects(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			match String(child.name):
				"Blobs", "StarFlares":
					(child as ColorRect).size     = Vector2(200.0, 200.0)
					(child as ColorRect).position = Vector2(-50.0, -50.0)
				_:
					(child as ColorRect).size     = Vector2(100.0, 100.0)
					(child as ColorRect).position = Vector2.ZERO
		_reset_star_colorrects(child)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG_COLOR)
	for col in range(COLS + 1):
		var x   := col * CELL
		var maj := col % 4 == 0
		draw_line(Vector2(x, 0), Vector2(x, 270),
			GRID_MAJOR if maj else GRID_MINOR, 1.0)
	for row in range(ROWS + 1):
		var y   := row * CELL
		var maj := row % 4 == 0
		draw_line(Vector2(0, y), Vector2(480, y),
			GRID_MAJOR if maj else GRID_MINOR, 1.0)
	for col in COLS:
		for row in ROWS:
			var pos := Vector2(col * CELL + 2, row * CELL + FONT_SIZE + 1)
			draw_string(FONT, pos, "%d,%d" % [col, row],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
