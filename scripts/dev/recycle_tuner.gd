extends Control

# RecycleTuner — Pillar 2, step 1 (the spec's mandated FIRST deliverable:
# docs/recycling_system_pillar2_2026-06-04.md). Live-tunes the enemy fly-back
# recycle: pre-cycle hold, re-entry inset, ghost scale/tint, fly-back duration +
# target. Persists to user://tuners/recycle.json via RecycleController (same source
# the runtime reads), so tuned values take effect in-game on next combat.
#
# Follows the house tuner contract (scripts/dev/ui_designer.gd): JSON save/load,
# Reset, Esc-to-close, and a mandatory Copy-GDScript button that emits a paste-ready
# RecycleController.DEFAULTS literal.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const RecycleController = preload("res://scripts/effects/recycle_controller.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")
const EnemyRosterC = preload("res://scripts/levels/enemy_roster.gd")
const EnemyManifestC = preload("res://scripts/dev/enemy_manifest.gd")

# Knob spec: key, label, min, max, step.
const KNOBS := [
	["hold_min", "Pre-cycle hold MIN (s)", 0.0, 3.0, 0.05],
	["hold_max", "Pre-cycle hold MAX (s)", 0.0, 3.0, 0.05],
	["entry_inset", "Re-entry inset (px)", 0.0, 60.0, 1.0],
	["fly_scale", "Ghost scale", 0.1, 1.0, 0.01],
	["fly_time", "Fly-back time (s)", 0.3, 5.0, 0.05],
	["fly_target_y", "Fly-back target Y (px)", -60.0, 40.0, 1.0],
	["tint_r", "Tint R", 0.0, 1.0, 0.01],
	["tint_g", "Tint G", 0.0, 1.0, 0.01],
	["tint_b", "Tint B", 0.0, 1.0, 0.01],
	["tint_a", "Tint A", 0.0, 1.0, 0.01],
]

var _values: Dictionary = {}
var _spins: Dictionary = {}        # key -> SpinBox
var _status_label: Label = null

# --- Preview state machine (mimics enemy_core._start_cycle timing) ---
# The ghost now flies in a native-480 SubViewport against a real backdrop + composed player +
# a few frozen enemies, so its recycle scale/tint can be judged against live game scale.
var _world: SubViewport = null
var _ghost: Node2D = null
var _ghost_base: Sprite2D = null   # a real enemy frame-0 sprite (scale/tint comparable)
var _phase: String = "hold"        # hold -> fly -> done(loop)
var _phase_t: float = 0.0
var _hold_dur: float = 0.7
var _from_y: float = 0.0
var _to_y: float = 0.0
var _entry_x: float = 0.0


var _hd_scope: HdViewportScope = null

func _ready() -> void:
	# Render at HD (1920×1080) instead of the cramped 480×270 native viewport, so the
	# knob rail + preview are actually usable (Roman 2026-06-11). Freed with the scene.
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_from_config()
	_build_ui()
	_build_preview()
	set_process(true)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


func _seed_from_config() -> void:
	var cfg := RecycleController.config()
	for spec in KNOBS:
		_values[spec[0]] = float(cfg.get(spec[0], RecycleController.DEFAULTS[spec[0]]))


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# Left rail: title + knobs + buttons.
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(360, 0)
	rail.add_theme_constant_override("separation", 6)
	root.add_child(rail)

	var title := Label.new()
	title.text = "RECYCLE TUNER"
	title.add_theme_font_size_override("font_size", 22)
	rail.add_child(title)

	for spec in KNOBS:
		rail.add_child(_make_knob_row(spec))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	rail.add_child(btn_row)
	_add_button(btn_row, "Save", _on_save)
	_add_button(btn_row, "Load", _on_load)
	_add_button(btn_row, "Reset", _on_reset)
	var btn_row2 := HBoxContainer.new()
	btn_row2.add_theme_constant_override("separation", 8)
	rail.add_child(btn_row2)
	_add_button(btn_row2, "Copy GDScript", _on_copy_snippet)
	_add_button(btn_row2, "Back (Esc)", _on_back)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_status_label.text = "Editing recycle.json"
	rail.add_child(_status_label)

	# Right: a native-480 SubViewport (3× upscale = 1440×810) showing the live game context.
	var svc := SubViewportContainer.new()
	svc.position = Vector2(400, 60)
	svc.stretch = true
	svc.stretch_shrink = 3   # 480*3 = 1440 wide; renders native, crisp 3× upscale
	svc.custom_minimum_size = Vector2(1440, 810)
	svc.size = Vector2(1440, 810)
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = SubViewport.new()
	_world.size = Vector2i(480, 270)
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# "bullet_world" sink so any parent-less fx from the backdrop/idle enemies resolve into this native
	# SubViewport, not the 1920×1080 window's top-left corner (BulletWorld.spawn_root; no-op in prod).
	_world.add_to_group("bullet_world")
	svc.add_child(_world)
	add_child(svc)


func _make_knob_row(spec: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = String(spec[1])
	lbl.custom_minimum_size = Vector2(210, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = float(spec[2])
	spin.max_value = float(spec[3])
	spin.step = float(spec[4])
	spin.value = float(_values[spec[0]])
	spin.custom_minimum_size = Vector2(110, 0)
	var key: String = String(spec[0])
	spin.value_changed.connect(func(v): _on_knob(key, v))
	row.add_child(spin)
	_spins[key] = spin
	return row


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_knob(key: String, v: float) -> void:
	_values[key] = v


# --- Live preview ---------------------------------------------------------

func _build_preview() -> void:
	if _world == null:
		return
	_spawn_backdrop()
	_spawn_idle_enemies()
	_spawn_player_visual()
	# The recycling subject — a real enemy frame-0 sprite (so its recycle scale/tint reads
	# against the live enemies), pinned ON TOP of the scene.
	_ghost = Node2D.new()
	_ghost.z_index = 50
	_world.add_child(_ghost)
	_ghost_base = _enemy_frame0_sprite(_random_enemy_scene())
	_ghost.add_child(_ghost_base)
	_restart_preview()


# Backdrop coordinator with an injected stellar context (a star + an asteroid belt) so the
# recycle reads against a real, non-empty backdrop instead of a bare panel.
func _spawn_backdrop() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null and "current_stellar" in run:
		run.current_stellar = {
			"planet_idx": 3, "planet_seed": 4242, "star_color": Color(0.8, 0.85, 1.0),
			"has_asteroids": true, "asteroid_density": 1.4,
			"nebula_band": "", "nebula_tint": Color.WHITE, "moons": [], "system": [],
		}
	var bd = BackdropCoordinatorScene.instantiate()
	bd.set("force_asteroids", true)
	_world.add_child(bd)


# A few frozen roster enemies scattered in the playfield band — process disabled so they
# hold position (no movement / firing / offscreen-cleanup), just visuals for scale compare.
func _spawn_idle_enemies() -> void:
	var ys := [70.0, 95.0, 120.0]
	for i in 3:
		var path := _random_enemy_scene()
		if path == "":
			continue
		var scn := load(path) as PackedScene
		if scn == null:
			continue
		var e = scn.instantiate()
		_world.add_child(e)
		if e is Node2D:
			e.position = Vector2(randf_range(Playfield.X_MIN + 16.0, Playfield.X_MAX - 16.0), ys[i])
		_freeze(e)


# Composed player ship at the bottom-centre of the band (cloned Sprite2D stack, mirroring
# enemy_bench._make_player_visual — no heavy player.gd _ready).
func _spawn_player_visual() -> void:
	var inst := PlayerScene.instantiate()
	var ship := inst.get_node_or_null("Ship") as Sprite2D
	var body := _clone_sprite(ship)
	if ship != null:
		for child in ship.get_children():
			if child is Sprite2D:
				var c := _clone_sprite(child)
				c.name = String(child.name)
				body.add_child(c)
	inst.free()
	body.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 24.0)
	body.z_index = 10
	_world.add_child(body)


func _clone_sprite(src: Sprite2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if src == null:
		return sp
	sp.texture = src.texture
	sp.hframes = src.hframes
	sp.vframes = src.vframes
	sp.frame = src.frame
	sp.flip_h = src.flip_h
	sp.flip_v = src.flip_v
	sp.position = src.position
	sp.modulate = src.modulate
	if src.material != null:
		sp.material = src.material.duplicate()
	return sp


# Frame-0 Sprite2D from an enemy scene (first Sprite2D descendant), for the ghost.
func _enemy_frame0_sprite(path: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if path == "":
		return sp
	var scn := load(path) as PackedScene
	if scn == null:
		return sp
	var inst = scn.instantiate()
	var src := _first_sprite(inst)
	if src != null:
		sp.texture = src.texture
		sp.hframes = src.hframes
		sp.vframes = src.vframes
		sp.frame = 0
	inst.free()
	return sp


func _first_sprite(n: Node) -> Sprite2D:
	if n is Sprite2D and (n as Sprite2D).texture != null:
		return n
	for ch in n.get_children():
		var r := _first_sprite(ch)
		if r != null:
			return r
	return null


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)


func _random_enemy_scene() -> String:
	# Full dev roster (incl. faction units) so the backdrop enemies vary across everything, not just
	# the production wave roll.
	var all: Array = EnemyManifestC.all_enemies(false)
	if all.is_empty():
		return ""
	return String(all[randi() % all.size()])


func _restart_preview() -> void:
	_phase = "hold"
	_phase_t = 0.0
	_hold_dur = randf_range(float(_values.hold_min), float(_values.hold_max))
	# Re-entry inset maps into the playfield band; fly_target_y is the native screen-space target.
	var inset: float = float(_values.entry_inset)
	_entry_x = randf_range(Playfield.X_MIN + inset, Playfield.X_MAX - inset)
	_from_y = Playfield.Y_MAX - 10.0
	_to_y = float(_values.fly_target_y)
	if _ghost:
		_ghost.position = Vector2(_entry_x, _from_y)
		_ghost.visible = false


func _process(delta: float) -> void:
	if _ghost == null:
		return
	_phase_t += delta
	match _phase:
		"hold":
			_ghost.visible = false
			if _phase_t >= _hold_dur:
				_phase = "fly"
				_phase_t = 0.0
				_ghost.visible = true
		"fly":
			var t: float = clampf(_phase_t / max(0.05, float(_values.fly_time)), 0.0, 1.0)
			var s: float = float(_values.fly_scale)
			_ghost.scale = Vector2(s, s)
			_ghost_base.modulate = RecycleController.tint(_values)
			_ghost.position = Vector2(_entry_x, lerp(_from_y, _to_y, t))
			if t >= 1.0:
				_phase = "done"
				_phase_t = 0.0
		"done":
			_ghost.visible = false
			if _phase_t >= 0.5:
				_restart_preview()


# --- Persistence + snippet ------------------------------------------------

func _on_save() -> void:
	if RecycleController.save(_values):
		_set_status("Saved → %s" % RecycleController.CONFIG_PATH)
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	RecycleController.invalidate()
	_seed_from_config()
	for key in _spins.keys():
		(_spins[key] as SpinBox).value = float(_values[key])
	_set_status("Loaded from disk")


func _on_reset() -> void:
	for spec in KNOBS:
		_values[spec[0]] = float(RecycleController.DEFAULTS[spec[0]])
		(_spins[spec[0]] as SpinBox).value = float(_values[spec[0]])
	_set_status("Reset to defaults")


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


# Emit a paste-ready RecycleController.DEFAULTS literal so tuned values can be
# baked into the controller's defaults.
func _build_snippet() -> String:
	var lines := PackedStringArray()
	lines.append("# Paste into scripts/effects/recycle_controller.gd (DEFAULTS):")
	lines.append("const DEFAULTS := {")
	lines.append("\t\"hold_min\": %.2f, \"hold_max\": %.2f," % [_values.hold_min, _values.hold_max])
	lines.append("\t\"entry_inset\": %.1f," % _values.entry_inset)
	lines.append("\t\"fly_scale\": %.2f, \"fly_time\": %.2f, \"fly_target_y\": %.1f," % [_values.fly_scale, _values.fly_time, _values.fly_target_y])
	lines.append("\t\"tint_r\": %.2f, \"tint_g\": %.2f, \"tint_b\": %.2f, \"tint_a\": %.2f," % [_values.tint_r, _values.tint_g, _values.tint_b, _values.tint_a])
	lines.append("}")
	return "\n".join(lines)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
