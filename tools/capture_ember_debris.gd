extends SceneTree

# Capture the ship debris ember effect: hero chunks tumbling out of a blast,
# wearing the damage_noise overlay shader, trailing hot embers + dark smoke,
# then disintegrating via pixelated_burn (Roman 2026-06-11). Pairs with
# ExplosionFx for context. ~2.6s @ 30fps with a re-fire ~1.3s in.
#
# Renders to the MAIN WINDOW viewport (NOT a SubViewport): the project's
# canvas_items stretch upscales 480-authored coords to the 1920×1080 window, and
# root.get_viewport().get_texture() grabs that — the pattern proven by
# capture_debris.gd. A SubViewport added to root never renders (no container /
# UPDATE_ALWAYS) → blank frames.

const OUT_DIR := "res://captures/ember_debris"
const FPS: int = 30
const DURATION: float = 2.6
const FRAME_TIME: float = 1.0 / float(FPS)

const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")


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
	# HDR 2D on the window so the HDR-bright embers bloom through the env glow.
	root.use_hdr_2d = true

	# Dark space background (native 480×270 logical space; canvas_items stretch
	# fills the 1920×1080 window).
	var bg := ColorRect.new()
	bg.color = Color(0.047, 0.055, 0.082, 1.0)  # ~#0c0e15
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)

	# WorldEnvironment glow so the ember sparks bloom (BG_CANVAS glow works on the
	# main viewport, same as main.tscn's combat bloom).
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.9
	we.environment = env
	root.add_child(we)

	# FX container (outlives any one debris spawn).
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)

	var burst_pos := Vector2(240, 110)
	seed(42)  # deterministic capture
	_spawn_debris_fan(stage, burst_pos)
	ExplosionFx.play(burst_pos, 1.5, true, stage)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		# Second burst ~1.3s in to keep the GIF lively as the first batch burns out.
		if f == 39:
			_spawn_debris_fan(stage, burst_pos)
			ExplosionFx.play(burst_pos, 0.8, true, stage)
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[ember-debris-gif] captured %d frames" % frame_count)
	quit()


# Fan of 5 debris chunks from `pos`, biased to the lower hemisphere (down + out).
func _spawn_debris_fan(stage: Node2D, pos: Vector2) -> void:
	for i in 5:
		var ang := randf_range(0.15, PI - 0.15)
		var spd := randf_range(50.0, 120.0)
		var vel := Vector2(cos(ang), sin(ang)) * spd
		ShipDebrisEmber.spawn(stage, pos, {
			"velocity": vel,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(0.9, 1.4),
			"lifetime": randf_range(1.5, 2.1),
		})
