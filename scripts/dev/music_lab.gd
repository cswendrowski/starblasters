extends Control

# Music Lab / Track Manager — Dev Menu tool for the Ovani music system.
#
# - Browse every track in assets/audio/music/ (auto-discovered from the
#   "Name (RT n.nn)" folders).
# - Select + listen, pan through Intensity 0..1 (the three phase-locked stems),
#   adjust volume, watch the loop point.
# - Assign which tracks are eligible for which game context (Main Menu, Sector
#   Map, Events, Outpost, Combat, Boss), then Save to the baked catalog
#   (res://resources/music/music_library.tres) the `Music` autoload reads.
#
# Edits a working COPY of the catalog; Save writes it back. Rescan re-reads the
# folders (preserving eligibility) so newly-dropped sets appear without losing
# assignments.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const MusicLibrary = preload("res://scripts/systems/music_library.gd")
const MusicLibraryData = preload("res://scripts/systems/music_library_data.gd")

const TRANSITION_SECS := 2.0
const INTENSITY_FADE_SECS := 4.0

var _hd_scope: HdViewportScope = null
var _player: OvaniPlayer = null
var _data: MusicLibraryData = null
var _lib: MusicLibrary = null

var _selected: String = ""
var _current_track: String = ""
var _track_buttons: Dictionary = {}   # name -> Button
var _elig_checks: Dictionary = {}     # context -> CheckBox

var _now_playing: Label = null
var _selected_label: Label = null
var _intensity_slider: HSlider = null
var _intensity_value: Label = null
var _volume_slider: HSlider = null
var _volume_value: Label = null
var _readout: Label = null
var _status: Label = null


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_dark_background()
	_build_data()
	_build_player()
	_build_ui()
	# Auto-select the first track so the lab boots playing something.
	var names := _lib.track_names()
	if not names.is_empty():
		_select_track(names[0])


func _install_dark_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	add_child(bg)
	move_child(bg, 0)


# ---- Data + player --------------------------------------------------------

func _build_data() -> void:
	if ResourceLoader.exists(MusicLibrary.DATA_PATH):
		_data = load(MusicLibrary.DATA_PATH).duplicate(true)
	else:
		_data = MusicLibraryData.new()
	_refresh_from_disk()
	_lib = MusicLibrary.new(_data)


func _refresh_from_disk() -> void:
	# Re-read folders, preserving existing eligibility; prune stale entries.
	_data.tracks = MusicLibrary.scan_project_folders()
	for ctx in MusicLibrary.CONTEXTS:
		var pool: Array = _data.eligibility.get(ctx, [])
		_data.eligibility[ctx] = pool.filter(func(n): return _data.tracks.has(n))


func _build_player() -> void:
	_player = OvaniPlayer.new()
	_player.name = "OvaniPlayer"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.Bus = "Music"
	_player.LoopQueue = false
	add_child(_player)
	_player.Volume = 0.0
	_player.Intensity = 0.0


# ---- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 32)
	root.add_theme_constant_override("margin_right", 32)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)

	var title := Label.new()
	title.text = "MUSIC LAB  ·  TRACK MANAGER"
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	col.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	body.add_child(_build_track_list())
	body.add_child(_build_control_panel())

	col.add_child(HSeparator.new())
	col.add_child(_build_bottom_bar())


func _build_track_list() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_constant_override("separation", 6)

	panel.add_child(_header("Tracks (%d)" % _lib.track_names().size()))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_track_buttons.clear()
	for track_name in _lib.track_names():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s   (RT %.3f)" % [track_name, _lib.reverb_tail(track_name)]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(btn, true)
		btn.pressed.connect(_select_track.bind(track_name))
		list.add_child(btn)
		_track_buttons[track_name] = btn

	return panel


func _build_control_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_now_playing = Label.new()
	UiTheme.style_label(_now_playing, UiTheme.LabelKind.HEADER)
	panel.add_child(_now_playing)

	# Intensity
	panel.add_child(_header("Intensity   I1  ◄———►  I2  ◄———►  Main"))
	_intensity_value = Label.new()
	UiTheme.style_label(_intensity_value, UiTheme.LabelKind.BODY)
	panel.add_child(_intensity_value)
	_intensity_slider = HSlider.new()
	_intensity_slider.min_value = 0.0
	_intensity_slider.max_value = 1.0
	_intensity_slider.step = 0.01
	_intensity_slider.custom_minimum_size = Vector2(0, 34)
	_intensity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intensity_slider.value_changed.connect(_on_intensity_slider)
	panel.add_child(_intensity_slider)

	var fade_row := HBoxContainer.new()
	fade_row.add_theme_constant_override("separation", 12)
	for preset in [["Calm (I1)", 0.0], ["Mid (I2)", 0.5], ["Peak (Main)", 1.0]]:
		var b := Button.new()
		b.text = "%s ▸%ss" % [preset[0], INTENSITY_FADE_SECS]
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b, true)
		b.pressed.connect(_on_fade_intensity.bind(float(preset[1])))
		fade_row.add_child(b)
	panel.add_child(fade_row)

	# Volume
	panel.add_child(_header("Volume (dB)"))
	_volume_value = Label.new()
	UiTheme.style_label(_volume_value, UiTheme.LabelKind.BODY)
	panel.add_child(_volume_value)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = -40.0
	_volume_slider.max_value = 6.0
	_volume_slider.step = 0.5
	_volume_slider.custom_minimum_size = Vector2(0, 34)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_slider)
	panel.add_child(_volume_slider)

	var stop_btn := Button.new()
	stop_btn.text = "■ Stop (2s fade)"
	stop_btn.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_button(stop_btn, true)
	stop_btn.pressed.connect(func(): _player.StopSongsNow(2); _current_track = "")
	panel.add_child(stop_btn)

	_readout = Label.new()
	UiTheme.style_label(_readout, UiTheme.LabelKind.CAPTION)
	panel.add_child(_readout)

	panel.add_child(HSeparator.new())

	# Eligibility editor
	_selected_label = Label.new()
	UiTheme.style_label(_selected_label, UiTheme.LabelKind.HEADER)
	panel.add_child(_selected_label)
	var elig_caption := Label.new()
	elig_caption.text = "Eligible in (check the game contexts this track may play in):"
	UiTheme.style_label(elig_caption, UiTheme.LabelKind.CAPTION)
	panel.add_child(elig_caption)

	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 18)
	_elig_checks.clear()
	for ctx in MusicLibrary.CONTEXTS:
		var cb := CheckBox.new()
		cb.text = MusicLibrary.CONTEXT_LABELS.get(ctx, ctx)
		cb.toggled.connect(_on_elig_toggled.bind(ctx))
		checks.add_child(cb)
		_elig_checks[ctx] = cb
	panel.add_child(checks)

	return panel


func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)

	var save := Button.new()
	save.text = "💾 Save catalog"
	save.custom_minimum_size = Vector2(220, 48)
	UiTheme.style_button(save, true)
	save.pressed.connect(_on_save)
	bar.add_child(save)

	var copy := Button.new()
	copy.text = "⧉ Copy GDScript"
	copy.custom_minimum_size = Vector2(220, 48)
	UiTheme.style_button(copy, true)
	copy.pressed.connect(_on_copy_gdscript)
	bar.add_child(copy)

	var rescan := Button.new()
	rescan.text = "↻ Rescan folders"
	rescan.custom_minimum_size = Vector2(220, 48)
	UiTheme.style_button(rescan, true)
	rescan.pressed.connect(_on_rescan)
	bar.add_child(rescan)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.style_label(_status, UiTheme.LabelKind.CAPTION)
	bar.add_child(_status)

	var back := Button.new()
	back.text = "Back (Esc)"
	back.custom_minimum_size = Vector2(180, 48)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	bar.add_child(back)

	return bar


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.HEADER)
	return l


# ---- Selection / playback -------------------------------------------------

func _select_track(track_name: String) -> void:
	_selected = track_name
	var song := _lib.make_song(track_name)
	if song != null:
		if _current_track == "":
			_player.QueueSong(song)
		else:
			_player.PlaySongNow(song, TRANSITION_SECS)
		_current_track = track_name
	# Sync list button toggle states.
	for n in _track_buttons:
		_track_buttons[n].set_pressed_no_signal(n == track_name)
	# Sync eligibility checkboxes to this track.
	for ctx in _elig_checks:
		var pool: Array = _data.eligibility.get(ctx, [])
		_elig_checks[ctx].set_pressed_no_signal(pool.has(track_name))
	if _selected_label != null:
		_selected_label.text = "Eligibility — %s" % track_name


func _on_intensity_slider(value: float) -> void:
	_player.Intensity = value
	_refresh_labels()


func _on_fade_intensity(target: float) -> void:
	_player.FadeIntensity(target, INTENSITY_FADE_SECS)
	_intensity_slider.set_value_no_signal(target)


func _on_volume_slider(value: float) -> void:
	_player.Volume = value
	_refresh_labels()


func _process(_delta: float) -> void:
	if _player == null or _readout == null:
		return
	if not _intensity_slider.has_focus():
		_intensity_slider.set_value_no_signal(_player.Intensity)
	_readout.text = "%s   |   %5.1fs / %5.1fs   |   intensity %.2f   (watch the loop point)" % [
		_current_track, _player.CurrentSongTime, _player.CurrentSongLength, _player.Intensity]
	_refresh_labels()


func _refresh_labels() -> void:
	if _now_playing != null:
		_now_playing.text = "▶ %s" % (_current_track if _current_track != "" else "(stopped)")
	if _intensity_value != null:
		_intensity_value.text = "intensity = %.2f   →   %s" % [_player.Intensity, _dominant_layer(_player.Intensity)]
	if _volume_value != null:
		_volume_value.text = "%.1f dB" % _player.Volume


func _dominant_layer(intensity: float) -> String:
	if intensity < 0.25:
		return "Intensity 1 (calm)"
	elif intensity < 0.75:
		return "Intensity 2 (mid)"
	return "Main (peak)"


# ---- Eligibility editing --------------------------------------------------

func _on_elig_toggled(pressed: bool, ctx: String) -> void:
	if _selected == "":
		return
	var pool: Array = _data.eligibility.get(ctx, [])
	if pressed and not pool.has(_selected):
		pool.append(_selected)
	elif not pressed:
		pool.erase(_selected)
	_data.eligibility[ctx] = pool
	_set_status("unsaved changes — %s %s %s" % [_selected, ("→" if pressed else "✕"), MusicLibrary.CONTEXT_LABELS.get(ctx, ctx)])


# ---- Save / copy / rescan -------------------------------------------------

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/music"))
	var err := ResourceSaver.save(_data, MusicLibrary.DATA_PATH)
	if err == OK:
		_set_status("saved %s" % MusicLibrary.DATA_PATH)
	else:
		_set_status("SAVE FAILED err=%d" % err)


func _on_copy_gdscript() -> void:
	var lines := ["# music eligibility (context -> tracks)", "{"]
	for ctx in MusicLibrary.CONTEXTS:
		var pool: Array = _data.eligibility.get(ctx, [])
		var quoted := pool.map(func(n): return "\"%s\"" % n)
		lines.append("\t\"%s\": [%s]," % [ctx, ", ".join(quoted)])
	lines.append("}")
	DisplayServer.clipboard_set("\n".join(lines))
	_set_status("copied eligibility GDScript to clipboard")


func _on_rescan() -> void:
	_refresh_from_disk()
	_lib = MusicLibrary.new(_data)
	_set_status("rescanned — %d tracks (re-open lab to refresh the list)" % _data.tracks.size())


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ---- Input + back ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


func _on_back() -> void:
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
