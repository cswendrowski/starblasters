extends SceneTree

# Render a few enemy sprites side-by-side with the damage_overlay shader
# slider sweeping from 0.0 → 1.0 and back, save a frame strip, then let
# ffmpeg stitch a GIF. Used to preview the shader range on real enemy art.

const OUT_DIR := "res://captures/damage_shader"
const FPS: int = 12
const DURATION: float = 4.0    # one full sweep 0 → 1 (capture half-cycle)
const FRAME_TIME: float = 1.0 / float(FPS)

const ENEMIES := [
	"res://scenes/enemies/enemy_diver.tscn",
	"res://scenes/enemies/enemy_cutter.tscn",
	"res://scenes/enemies/enemy_frigate.tscn",
	"res://scenes/enemies/enemy_bulwark.tscn",
]
const SHADER := preload("res://graphics/damage_overlay.gdshader")


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
	# Backdrop so the sprites read clearly against a dark playfield.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# Centered row of sprites with damage shader applied.
	var sprites: Array[Sprite2D] = []
	var mats: Array[ShaderMaterial] = []
	var labels: Array[Label] = []
	var row_y: float = 200.0
	var gap: float = 80.0
	for i in ENEMIES.size():
		var ps := load(ENEMIES[i]) as PackedScene
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		# Find the Sprite2D under the enemy root.
		var spr: Sprite2D = _find_sprite(inst)
		if spr == null:
			inst.queue_free()
			continue
		# Detach from the enemy and parent the sprite directly so we can
		# position it without dragging the rest of the scene's collision /
		# audio / particle nodes.
		spr.get_parent().remove_child(spr)
		spr.scale = Vector2(3.0, 3.0)
		var x: float = 60.0 + float(i) * gap
		spr.position = Vector2(x, row_y)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("damage_level", 0.0)
		spr.material = mat
		root.add_child(spr)
		sprites.append(spr)
		mats.append(mat)
		inst.queue_free()
		# Label under sprite with the enemy name.
		var name_str: String = ENEMIES[i].get_file().get_basename()
		if name_str.begins_with("enemy_"):
			name_str = name_str.substr(6)
		var lbl := Label.new()
		lbl.text = name_str.capitalize()
		lbl.position = Vector2(x - 28, row_y + 28)
		lbl.size = Vector2(56, 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		root.add_child(lbl)
		labels.append(lbl)
	# Slider readout above the row.
	var slider_label := Label.new()
	slider_label.text = "damage_level 0.00"
	slider_label.position = Vector2(80, 60)
	slider_label.size = Vector2(160, 16)
	slider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider_label.add_theme_font_size_override("font_size", 12)
	root.add_child(slider_label)
	# Settle a frame so textures bind.
	await create_timer(0.2).timeout
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(max(1, frame_count - 1))
		# Linear sweep 0 → 1.
		var lvl: float = clamp(t, 0.0, 1.0)
		for m in mats:
			m.set_shader_parameter("damage_level", lvl)
		slider_label.text = "damage_level %.2f" % lvl
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[damage-gif] captured %d frames" % frame_count)
	quit()


func _find_sprite(n: Node) -> Sprite2D:
	if n is Sprite2D:
		return n
	for c in n.get_children():
		var hit := _find_sprite(c)
		if hit:
			return hit
	return null
