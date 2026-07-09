extends Control

# Combat VFX Lab (Roman 2026-06-21) — a LIVE combat-style stage for tuning the WorldEnvironment
# bloom + the per-category HDR-bright glow against real motion. A regenerating parallax backdrop,
# random enemy ships that fly down and shoot, live WorldEnv glow knobs, and per-category HDR-modulate
# sliders (bullets / engines / lasers / explosions / particles) shared with the Shader Lab "Glow" tab.
#
# Self-contained: it HDR-modulates THIS lab's own live + demo nodes by the shared VfxGlowConfig — no
# production code runs the glow, so nothing leaks back into combat. Copy GDScript + Save exports the table.
#
# Mirrors the shader_lab HD scaffold: native 480×270 SubViewport (use_hdr_2d) in a SubViewportContainer
# (stretch_shrink=4), an HD overlay CanvasLayer with the knob rail.

const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const StellarComposer = preload("res://scripts/parallax/stellar_composer.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const VfxGlowConfigC = preload("res://scripts/effects/vfx_glow_config.gd")  # shared per-category HDR mults
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")

# Bullet payloads cycled at random for ambiance.
const PAYLOADS := [
	preload("res://data/bullets/ball.tres"),
	preload("res://data/bullets/wave.tres"),
	preload("res://data/bullets/laser.tres"),
	preload("res://data/bullets/orb.tres"),
	preload("res://data/bullets/bolt.tres"),
]

# A curated spawn pool: small/medium common+uncommon ships, no mines/hazards/bosses (they don't
# read as "flying ships"). Resolved from EnemyRoster.ENTRIES at _ready.
const SKIP_TAGS := ["mine", "hazard"]

const FS_HEADER := 34
const FS_BODY := 17
const FS_CAPTION := 14
const RAIL_W := 300

var _hd_scope = null
var _vp: SubViewport = null
var _stage: Node2D = null          # gameplay layer (group "bullet_world") — enemies + bullets
var _backdrop: Node2D = null
var _env: Environment = null
var _knob_box: VBoxContainer = null
var _rng := RandomNumberGenerator.new()
var _spawn_pool: Array = []
var _spawn_accum: float = 0.0

# Live-tunable state.
var _env_vals := {
	"glow_intensity": 0.8, "glow_strength": 0.7, "glow_bloom": 0.0, "glow_hdr_threshold": 1.5,
	"contrast": 1.08, "saturation": 1.12,
}
var _glow_enabled := true
var _blend_mode := 1               # Environment.GLOW_BLEND_MODE_SCREEN
var _spawn_rate := 1.4             # ships/sec
# Demo-VFX cadence accumulators — laser / explosion / ember spawns so the laser/explosion/particle
# glow categories have something live to tune (this is an enemy-only scene; they don't occur on their own).
var _laser_t := 0.0
var _expl_t := 0.0
var _ember_t := 0.0

const BLEND_NAMES := ["Additive", "Screen", "Softlight", "Replace", "Mix"]


var _run_snapshot := {}

func _ready() -> void:
	_rng.randomize()
	VfxGlowConfigC.ensure_loaded()
	# Snapshot the autoload Run fields the backdrop uses so the lab's re-rolls don't leak into a
	# later combat session (restored in _exit_tree).
	var run = get_node_or_null("/root/Run")
	if run != null:
		_run_snapshot = {"stellar": run.current_stellar, "seed": run.run_seed, "node": run.current_node_id}
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	_build_pool()
	_build_playspace()
	_build_overlay()
	_regenerate_backdrop()
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_vp, "Combat VFX Lab")


func _build_pool() -> void:
	for entry in EnemyRoster.ENTRIES:
		var e: Dictionary = entry
		var sz := String(e.get("size", "small"))
		if sz != "small" and sz != "medium":
			continue
		var tags: Array = e.get("tags", [])
		var skip := false
		for t in SKIP_TAGS:
			if t in tags:
				skip = true
		if skip:
			continue
		if String(e.get("scene", "")).contains("mine"):
			continue
		_spawn_pool.append(e)


# ---- Playspace (native 480×270 SubViewport) --------------------------------

func _build_playspace() -> void:
	var sub := SubViewportContainer.new()
	sub.stretch = true
	sub.stretch_shrink = 4   # keep the SubViewport NATIVE 480×270 (stretch=true alone clobbers .size)
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	_vp = SubViewport.new()
	_vp.size = Vector2i(480, 270)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	_vp.use_hdr_2d = true   # required for the WorldEnvironment bloom + additive glows to composite
	sub.add_child(_vp)
	# Gameplay layer — enemies + their bullets live here. In "bullet_world" so bespoke firers
	# (turrets/beamers/drops) resolve their projectiles into THIS viewport, not the window corner.
	_stage = Node2D.new()
	_stage.name = "Gameplay"
	_stage.add_to_group("bullet_world")
	_vp.add_child(_stage)
	# Hidden dummy player low in the band so AT_PLAYER / aimed shots point downward convincingly.
	var dummy := Area2D.new()
	dummy.name = "DummyPlayer"
	dummy.add_to_group("player")
	dummy.position = Vector2(Playfield.CENTER.x, 250.0)
	dummy.visible = false
	_stage.add_child(dummy)
	# WorldEnvironment (combat bloom).
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS
	_env.glow_enabled = true
	we.environment = _env
	_vp.add_child(we)
	_apply_env()


# ---- Backdrop --------------------------------------------------------------

func _regenerate_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	# Re-roll the stellar config + a fresh run seed so the layout varies each regen.
	# (Autoload accessed via /root path so the headless compile-check doesn't choke on a bare `Run`.)
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.current_stellar = StellarComposer.compose(_rng)
		run.run_seed = _rng.randi()
		run.current_node_id = "vfxlab_%d" % _rng.randi()
	_backdrop = BackdropCoordinatorScene.instantiate()
	if "drift_speed" in _backdrop:
		_backdrop.drift_speed = 22.0
	if "force_asteroids" in _backdrop:
		_backdrop.force_asteroids = true
	# Behind the gameplay layer (earlier sibling draws first).
	_vp.add_child(_backdrop)
	_vp.move_child(_backdrop, 0)


# ---- WorldEnvironment ------------------------------------------------------

func _apply_env() -> void:
	if _env == null:
		return
	_env.glow_enabled = _glow_enabled
	_env.glow_intensity = _env_vals["glow_intensity"]
	_env.glow_strength = _env_vals["glow_strength"]
	_env.glow_bloom = _env_vals["glow_bloom"]
	_env.glow_hdr_threshold = _env_vals["glow_hdr_threshold"]
	_env.glow_blend_mode = _blend_mode
	_env.adjustment_enabled = true
	_env.adjustment_contrast = _env_vals["contrast"]
	_env.adjustment_saturation = _env_vals["saturation"]


# ---- Spawning --------------------------------------------------------------

func _process(delta: float) -> void:
	# Continuous random ship spawns.
	if not _spawn_pool.is_empty():
		_spawn_accum += delta * _spawn_rate
		while _spawn_accum >= 1.0:
			_spawn_accum -= 1.0
			_spawn_ship()
	# Periodic demo VFX so the laser / explosion / particle categories have something live to tune.
	_laser_t += delta
	_expl_t += delta
	_ember_t += delta
	if _laser_t >= 1.1:
		_laser_t = 0.0
		_spawn_demo_laser()
	if _expl_t >= 2.2:
		_expl_t = 0.0
		_spawn_demo_explosion()
	if _ember_t >= 0.8:
		_ember_t = 0.0
		_spawn_demo_particles()
	# Apply each category's HDR-bright modulate to every live VFX node each frame (they churn fast).
	_apply_vfx_glow()


func _spawn_ship() -> void:
	var entry: Dictionary = _spawn_pool[_rng.randi() % _spawn_pool.size()]
	var ps := load(String(entry["scene"])) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	if "movement" in inst:
		inst.movement = EnemyRoster.make_movement(entry)
	if "shoot_pattern" in inst:
		inst.shoot_pattern = _make_weapon()
		if "fire_on_phase" in inst:
			inst.fire_on_phase = ""   # use the generic ShootTimer cadence
	# Sane locomotion + survivability (nothing shoots them; keep them flying through).
	if "max_health" in inst:
		inst.max_health = 9999
	if "display_scale" in inst:
		inst.display_scale = 1.0
	var loco: Dictionary = EnemyRoster.resolve_locomotion(entry)
	for k in ["move_speed", "weight", "turn_rate", "accel", "depth_bp"]:
		if k in inst and loco.has(k):
			inst.set(k, float(loco[k]))
	var x := _rng.randf_range(Playfield.X_MIN + 12.0, Playfield.X_MAX - 12.0)
	var spawn_pos := Vector2(x, -20.0)
	if inst is Node2D:
		(inst as Node2D).position = spawn_pos
	_stage.add_child(inst)
	if inst.has_method("start"):
		inst.start(spawn_pos)


func _make_weapon() -> Resource:
	var w = Weapon.new()
	w.fire_pattern = [Weapon.FirePattern.SINGLE, Weapon.FirePattern.AIMED, Weapon.FirePattern.SPREAD][_rng.randi() % 3]
	w.aim = [Weapon.Aim.STRAIGHT_DOWN, Weapon.Aim.AT_PLAYER, Weapon.Aim.TOWARD_CENTER][_rng.randi() % 3]
	w.payload = PAYLOADS[_rng.randi() % PAYLOADS.size()]
	w.spread_count = 3
	w.spread_degrees = 22.0
	w.fire_interval_min = 0.7
	w.fire_interval_max = 1.6
	return w


# ---- Per-category HDR glow (shared VfxGlowConfig, driven by the rail sliders) ----------------
# Every live VFX node is HDR-modulated by its category multiplier so the WorldEnvironment blooms it.
# Bullets + engine glowmasks/trails come from the live ships; lasers/explosions/particles are the
# periodic lab-spawned demos. Walked every frame because all of these churn.

func _apply_vfx_glow() -> void:
	for b in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b):
			var spr := _find_bullet_sprite(b)
			if spr != null:
				spr.modulate = VfxGlowConfigC.hdr("bullets")
	_walk_vfx(_stage, false)


func _walk_vfx(n: Node, under_expl: bool) -> void:
	for c in n.get_children():
		var ux: bool = under_expl or c.is_in_group("vfx_explosion")
		if c is GPUParticles2D or c is CPUParticles2D:
			(c as CanvasItem).modulate = VfxGlowConfigC.hdr("particles")
		elif c is Line2D:
			(c as Line2D).modulate = VfxGlowConfigC.hdr("lasers" if c.is_in_group("vfx_laser") else "engines")
		elif c is Sprite2D and String(c.name) == "GlowMask":
			(c as Sprite2D).modulate = VfxGlowConfigC.hdr("engines")
		elif ux and (c is Sprite2D or c is AnimatedSprite2D):
			(c as CanvasItem).modulate = VfxGlowConfigC.hdr("explosions")
		_walk_vfx(c, ux)


func _find_bullet_sprite(b: Node) -> CanvasItem:
	for c in b.get_children():
		if c is Sprite2D or c is AnimatedSprite2D:
			return c
	return null


# ---- Demo VFX for the laser / explosion / particle categories --------------

func _spawn_demo_laser() -> void:
	var x := _rng.randf_range(Playfield.X_MIN + 20.0, Playfield.X_MAX - 20.0)
	var line := Line2D.new()
	line.add_to_group("vfx_laser")
	line.width = 3.0
	line.default_color = Color(0.55, 0.78, 1.0, 1.0)
	line.add_point(Vector2(x, 14.0))
	line.add_point(Vector2(x, 256.0))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat
	line.z_index = 1
	_stage.add_child(line)
	var tw := line.create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(line.queue_free)


func _spawn_demo_explosion() -> void:
	var pos := Vector2(_rng.randf_range(Playfield.X_MIN + 24.0, Playfield.X_MAX - 24.0), _rng.randf_range(60.0, 200.0))
	var node = ExplosionFx.play_config(pos, {"size": 0.9}, _stage)
	if node != null and node is Node:
		(node as Node).add_to_group("vfx_explosion")


func _spawn_demo_particles() -> void:
	var pos := Vector2(_rng.randf_range(Playfield.X_MIN + 24.0, Playfield.X_MAX - 24.0), _rng.randf_range(80.0, 220.0))
	var p = EmberFx.spray(_stage, pos, Vector2.UP, {"amount": 16})
	if p != null:
		var tw := p.create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(p.queue_free)


# ---- Overlay / knob rail ---------------------------------------------------

func _build_overlay() -> void:
	var ov := CanvasLayer.new()
	ov.layer = 5
	add_child(ov)
	# Header.
	var title := _label("Combat VFX Lab", FS_HEADER, UiTheme.COLOR_ACCENT)
	title.position = Vector2(40, 24)
	ov.add_child(title)
	var back := Button.new()
	back.text = "‹ Back"
	UiTheme.style_button(back, false)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.position = Vector2(40, 80)
	back.custom_minimum_size = Vector2(120, 44)
	back.pressed.connect(func(): SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn"))
	ov.add_child(back)
	# Rail panel on the right.
	var panel := PanelContainer.new()
	panel.position = Vector2(1920 - RAIL_W - 40, 24)
	panel.custom_minimum_size = Vector2(RAIL_W, 1080 - 80)
	ov.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(RAIL_W, 1080 - 120)
	panel.add_child(scroll)
	_knob_box = VBoxContainer.new()
	_knob_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_knob_box.custom_minimum_size = Vector2(RAIL_W - 24, 0)
	_knob_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_knob_box)

	_section("Scene")
	_button("⟳ Regenerate Background", _regenerate_backdrop)
	_slider("Spawn rate (ships/s)", 0.0, 5.0, 0.1, _spawn_rate, func(v): _spawn_rate = v)

	_section("VFX HDR Glow (modulate ×)")
	for cat in VfxGlowConfigC.CATEGORIES:
		_glow_slider(String(cat))
	_button("⧉ Copy GDScript + Save", _copy_vfx_glow)

	_section("WorldEnvironment")
	_check("Glow enabled", _glow_enabled, func(on):
		_glow_enabled = on
		_apply_env())
	_dropdown("Blend mode", BLEND_NAMES, _blend_mode, func(i):
		_blend_mode = i
		_apply_env())
	_env_slider("Intensity", "glow_intensity", 0.0, 4.0, 0.05)
	_env_slider("Strength", "glow_strength", 0.0, 2.0, 0.05)
	_env_slider("Bloom", "glow_bloom", 0.0, 1.0, 0.02)
	_env_slider("HDR threshold", "glow_hdr_threshold", 0.0, 2.0, 0.05)
	_env_slider("Contrast", "contrast", 0.5, 1.5, 0.01)
	_env_slider("Saturation", "saturation", 0.5, 1.5, 0.01)


func _section(text: String) -> void:
	var sep := HSeparator.new()
	_knob_box.add_child(sep)
	_knob_box.add_child(_label(text, FS_BODY, UiTheme.COLOR_ACCENT))


func _glow_slider(cat: String) -> void:
	_slider(cat.capitalize(), VfxGlowConfigC.SLIDER_MIN, VfxGlowConfigC.SLIDER_MAX, 0.05,
		VfxGlowConfigC.get_mult(cat), func(v): VfxGlowConfigC.set_mult(cat, v))


func _copy_vfx_glow() -> void:
	DisplayServer.clipboard_set(VfxGlowConfigC.snippet())
	VfxGlowConfigC.save()


func _env_slider(label: String, key: String, lo: float, hi: float, step: float) -> void:
	_slider(label, lo, hi, step, float(_env_vals[key]), func(v):
		_env_vals[key] = v
		_apply_env())


func _slider(label: String, lo: float, hi: float, step: float, val: float, cb: Callable) -> void:
	var row := _label("%s: %.2f" % [label, val], FS_CAPTION, UiTheme.COLOR_FAINT)
	_knob_box.add_child(row)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(0, 26)
	sl.value_changed.connect(func(v: float):
		row.text = "%s: %.2f" % [label, v]
		cb.call(v))
	_knob_box.add_child(sl)


func _check(label: String, val: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = val
	c.add_theme_font_size_override("font_size", FS_BODY)
	c.toggled.connect(func(on: bool): cb.call(on))
	_knob_box.add_child(c)


func _button(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	UiTheme.style_button(b, true)
	b.add_theme_font_size_override("font_size", FS_BODY)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	_knob_box.add_child(b)


func _dropdown(label: String, items: Array, sel: int, cb: Callable) -> void:
	_knob_box.add_child(_label(label, FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for it in items:
		dd.add_item(String(it))
	dd.select(sel)
	dd.item_selected.connect(func(i: int): cb.call(i))
	_knob_box.add_child(dd)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _exit_tree() -> void:
	# Restore the Run fields the backdrop regen overwrote so combat doesn't inherit lab state.
	var run = get_node_or_null("/root/Run")
	if run != null and not _run_snapshot.is_empty():
		run.current_stellar = _run_snapshot["stellar"]
		run.run_seed = _run_snapshot["seed"]
		run.current_node_id = _run_snapshot["node"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
