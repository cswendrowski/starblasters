extends SceneTree

# Drop shadow POC (Roman 2026-05-18). Player flies over large asteroids;
# the topdown_shadow shader paints a shadow of the ship, and the
# asteroid clips the shadow to its own opaque pixels via clip_children
# so the shadow only appears WHERE there's an asteroid under the ship.

const OUT_DIR := "res://captures/shadow_test"
const FPS: int = 24
const DURATION: float = 6.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/topdown_shadow_outofbounds.gdshader")
const ASTEROID_SCENE := preload("res://Planets/Asteroids/Asteroid.tscn")
const PLAYER_TEX := preload("res://graphics/player/blue-fighter-sheet.png")


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _run() -> void:
	# Dark BG.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)
	# Three large asteroids — spaced so they don't overlap, so the
	# "which asteroid is under the player" pick is unambiguous.
	var asteroid_positions := [Vector2(50, 220), Vector2(160, 200), Vector2(270, 240)]
	var asteroids: Array = []
	for ap in asteroid_positions:
		# Asteroid root is a Control — bind as Node so we can mix types.
		var a = ASTEROID_SCENE.instantiate() as Node
		if a is Control:
			(a as Control).position = ap
			(a as Control).scale = Vector2(2.5, 2.5)
		elif a is Node2D:
			(a as Node2D).position = ap
			(a as Node2D).scale = Vector2(2.5, 2.5)
		root.add_child(a)
		asteroids.append(a)
	# Player sprite (single 16×16 frame from the player sheet).
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1   # default forward-facing frame
	player.scale = Vector2(3, 3)
	player.z_index = 10
	root.add_child(player)
	# Single shadow sprite using the topdown_shadow shader. Direct child
	# of root with z_index between asteroids (0) and player (10). Each
	# frame we hit-test the player position against all asteroid bounds;
	# if any contain the player, the shadow is visible at the player
	# position. Otherwise hidden. Simpler than per-asteroid clipping and
	# guarantees a single shadow (Roman 2026-05-18).
	var shadow := Sprite2D.new()
	shadow.texture = PLAYER_TEX
	shadow.hframes = 3
	shadow.frame = 1
	shadow.scale = Vector2(3, 3)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("r", 0.0)
	mat.set_shader_parameter("offset", 0.0)
	mat.set_shader_parameter("shadow_only", true)
	shadow.material = mat
	shadow.z_index = 5
	shadow.visible = false
	root.add_child(shadow)
	# Hit-test bounds per asteroid (approximate rect around the visible
	# drawer). Computed once after all asteroids are spawned.
	var asteroid_rects: Array = []
	for a in asteroids:
		var clipper: CanvasItem = _find_first_drawer(a)
		if clipper == null:
			continue
		var center: Vector2 = Vector2.ZERO
		var sz: Vector2 = Vector2(60, 60)
		if clipper is Node2D:
			center = (clipper as Node2D).global_position
		elif clipper is Control:
			var ctrl := clipper as Control
			center = ctrl.global_position + ctrl.size * ctrl.scale * 0.5
			sz = ctrl.size * ctrl.scale
		asteroid_rects.append(Rect2(center - sz * 0.5, sz))
	# Capture loop — slide player across the screen.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		# Sine slide left-right + slight up-down.
		var x: float = 160.0 + 110.0 * sin(t * TAU * 0.25)
		var y: float = 200.0 + 14.0 * sin(t * TAU * 0.5)
		player.position = Vector2(x, y)
		# Hit-test player against asteroid rects. Shadow appears at the
		# player's position (with a slight drop offset) when the player
		# is over any asteroid; vanishes entirely over empty space.
		var over_asteroid: bool = false
		for rect in asteroid_rects:
			if (rect as Rect2).has_point(player.global_position):
				over_asteroid = true
				break
		shadow.visible = over_asteroid
		if over_asteroid:
			shadow.global_position = player.global_position + Vector2(6, 8)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[shadow-test] captured %d frames" % frame_count)
	quit()


func _find_first_drawer(n: Node) -> CanvasItem:
	# The first CanvasItem child we hit that actually draws something
	# (ColorRect, Sprite2D, TextureRect). Used as the clip parent.
	for c in n.get_children():
		if c is Sprite2D or c is ColorRect or c is TextureRect:
			return c
		var hit := _find_first_drawer(c)
		if hit:
			return hit
	if n is Sprite2D or n is ColorRect or n is TextureRect:
		return n
	return null
