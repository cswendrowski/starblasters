extends SceneTree

# Capture the per-bullet-style glow_effect_2d looks tuned in the Shader Lab (Roman 2026-06-20).
# Reads the saved per-style params from user://tuners/shader_lab.json (GlowStyles) and renders each
# bullet — raw (left) vs glow_effect_2d (right) — into a 480x270 HDR SubViewport with the SAME
# WorldEnvironment the tuner used (glow on, intensity 0.8, hdr_threshold 0.9), one labelled frame
# per style. MUST run WITHOUT --headless (the glow shader + bloom need a real GPU).

const OUT_DIR := "res://captures/bullet_glow_styles"
const GLOW_SHADER: Shader = preload("res://graphics/glow_effect_2d.gdshader")
const ShaderLabScript = preload("res://scripts/dev/shader_lab.gd")  # reuse the exact style list
const TUNER_JSON := "user://tuners/shader_lab.json"
const ZOOM := 5.0

var _sv: SubViewport = null
var _content: Node2D = null
var _cfg: Dictionary = {}


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
	_cfg = _load_cfg()
	_sv = SubViewport.new()
	_sv.size = Vector2i(480, 270)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.use_hdr_2d = true   # match the Shader Lab tuner so intensity reads the same
	root.add_child(_sv)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.05)
	bg.size = Vector2(480, 270)
	_sv.add_child(bg)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 0.9
	we.environment = env
	_sv.add_child(we)
	_content = Node2D.new()
	_sv.add_child(_content)

	var frame := 0
	for spec in ShaderLabScript.GLOW_BULLET_STYLES:
		var nm := String(spec["name"])
		var res := _resolve(spec)
		if res["tex"] == null:
			print("[glow-cap] SKIP (no tex): ", nm)
			continue
		_clear(_content)
		var cfg: Dictionary = _cfg.get(nm, {})
		var tex: Texture2D = res["tex"]
		var fr := int(res["frames"])
		_sprite(Vector2(240.0 - 64.0, 140.0), tex, fr, null)         # raw
		_sprite(Vector2(240.0 + 64.0, 140.0), tex, fr, _mat(cfg))    # glow_effect_2d
		_label(nm, 18, Color(0.95, 0.97, 1.0), Vector2(0, 22), 480, HORIZONTAL_ALIGNMENT_CENTER)
		_label("raw", 13, Color(0.7, 0.75, 0.8), Vector2(240 - 110, 190), 92, HORIZONTAL_ALIGNMENT_CENTER)
		_label("glow", 13, Color(0.7, 0.85, 1.0), Vector2(240 + 18, 190), 92, HORIZONTAL_ALIGNMENT_CENTER)
		# Let the new content + glow fully draw before grabbing one settled frame.
		for _i in 5:
			await create_timer(0.03).timeout
		await RenderingServer.frame_post_draw
		var img: Image = _sv.get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, frame]))
			print("[glow-cap] %02d  %-18s bright_px=%d" % [frame, nm, _bright_count(img)])
			frame += 1
	print("[glow-cap] captured %d frames -> %s" % [frame, OUT_DIR])
	quit()


func _load_cfg() -> Dictionary:
	if not FileAccess.file_exists(TUNER_JSON):
		print("[glow-cap] no tuner json (", TUNER_JSON, ") — falling back to white defaults")
		return {}
	var f := FileAccess.open(TUNER_JSON, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return (data as Dictionary).get("GlowStyles", {})
	return {}


func _mat(cfg: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("color1", Color(String(cfg.get("color1", "ffffffff"))))
	m.set_shader_parameter("color2", Color(String(cfg.get("color2", "ffffffff"))))
	m.set_shader_parameter("glow_color", Color(String(cfg.get("glow_color", "ffffffff"))))
	m.set_shader_parameter("threshold", float(cfg.get("threshold", 0.45)))
	m.set_shader_parameter("intensity", float(cfg.get("intensity", 1.8)))
	m.set_shader_parameter("opacity", float(cfg.get("opacity", 1.0)))
	return m


func _sprite(pos: Vector2, tex: Texture2D, frames: int, mat: ShaderMaterial) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if frames > 1:
		s.hframes = frames
		s.frame = 0
	s.scale = Vector2(ZOOM, ZOOM)
	s.position = pos
	if mat != null:
		s.material = mat
	_content.add_child(s)


func _label(txt: String, sz: int, col: Color, pos: Vector2, width: float, align: int) -> void:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = Vector2(width, 20)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	_content.add_child(l)


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.free()


func _resolve(spec: Dictionary) -> Dictionary:
	if spec.has("variant"):
		var v = load(String(spec["variant"]))
		var fc := 1
		if v != null and ("frame_count" in v):
			fc = maxi(int(v.frame_count), 1)
		var tex = null
		if v != null:
			if ("sprite_frames" in v) and v.sprite_frames != null:
				var names = v.sprite_frames.get_animation_names()
				if names.size() > 0 and v.sprite_frames.get_frame_count(names[0]) > 0:
					tex = v.sprite_frames.get_frame_texture(names[0], 0)
			if tex == null and ("static_texture" in v):
				tex = v.static_texture
		return {"tex": tex, "frames": fc}
	if spec.has("scene"):
		var res := {"tex": null, "frames": 1}
		var ps = load(String(spec["scene"])) as PackedScene
		if ps != null:
			var inst = ps.instantiate()
			var spr = _find_sprite(inst)
			if spr is Sprite2D:
				res["tex"] = (spr as Sprite2D).texture
				res["frames"] = maxi((spr as Sprite2D).hframes, 1)
			elif spr is AnimatedSprite2D and (spr as AnimatedSprite2D).sprite_frames != null:
				var asp = spr as AnimatedSprite2D
				var names = asp.sprite_frames.get_animation_names()
				if names.size() > 0 and asp.sprite_frames.get_frame_count(names[0]) > 0:
					res["tex"] = asp.sprite_frames.get_frame_texture(names[0], 0)
			inst.free()
		return res
	return {"tex": null, "frames": 1}


func _find_sprite(n: Node) -> Node:
	for c in n.get_children():
		if c is Sprite2D or c is AnimatedSprite2D:
			return c
		var f = _find_sprite(c)
		if f != null:
			return f
	return null


# Coarse brightness stat (NOT a visual read) so the run can self-report each style actually lit up.
func _bright_count(img: Image) -> int:
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	var x := 0
	while x < w:
		var y := 0
		while y < h:
			var c := img.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > 0.6:
				n += 1
			y += 4
		x += 4
	return n
