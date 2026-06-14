extends Node

# Persistent player settings — autoloaded as `Settings`. One source of
# truth for the Options menu (whether opened from the main menu or the
# in-game pause menu). All values are persisted to user://settings.cfg on
# any apply() call and re-loaded on _ready() so a setting set on the title
# screen survives into a run, and a setting tweaked mid-pause survives
# back to the menu.

signal settings_changed

const CFG_PATH := "user://settings.cfg"

# Audio (Master bus, linear 0..1)
var master_volume: float = 1.0
# Music (Music bus, linear 0..1). Falls back silently if no Music bus
# exists; the property is still honored by music_manager via its own
# scaling.
var music_volume: float = 1.0
# Sound effects (SFX bus, linear 0..1). All non-music audio routes through
# the SFX bus (see scripts/effects/* + the player/enemy audio nodes).
var sfx_volume: float = 1.0
# Screen shake intensity multiplier (0 disables shake entirely; 1 = stock).
var shake_scale: float = 1.0
# Fullscreen window mode (false = windowed, the project default).
var fullscreen: bool = false
# Font face: "pixel" = Pixel Operator (default, designed for small sizes),
# "ttf" = Pixelify Sans (smoother TTF alternative). Toggled in the
# Options menu; saved on change.
var font_style: String = "pixel"
# Autofire — when true, primary fire latches on automatically without
# the player holding the button. Cannon-only: equivalent to holding the
# "shoot" button continuously. Secondary/super inputs are unaffected.
# RUNTIME-ONLY (Roman, 2026-05-24): NOT persisted to settings.cfg, so
# every fresh launch starts with autofire off. Toggled in-game via the
# rebindable "autofire_toggle" action (default R).
var autofire: bool = false
# Keybind overrides — { action_name: physical_keycode }. Replaces the
# first keyboard event on each action when the override is set.
# Empty = use project.godot defaults.
var keyboard_overrides: Dictionary = {}


func _ready() -> void:
	load_from_disk()
	_apply_audio()
	_apply_window()
	_apply_keybinds()
	# Push the saved font face into the project theme so every Control picks
	# it up (and so Pixel Operator renders crisp — AA/hinting forced off in
	# UiTheme.active_font()). Deferred: the project theme may not be loaded
	# into ThemeDB yet during autoload init.
	call_deferred("_apply_font")


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	music_volume = float(cfg.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", sfx_volume))
	shake_scale = float(cfg.get_value("video", "shake_scale", shake_scale))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	font_style = String(cfg.get_value("video", "font_style", font_style))
	# autofire intentionally NOT loaded — runtime-only, defaults off each launch.
	# Keybind overrides — stored as a JSON-serialised dict (ConfigFile
	# doesn't natively round-trip Dictionary cleanly across versions).
	var raw_overrides := String(cfg.get_value("controls", "keyboard_overrides", "{}"))
	var parsed = JSON.parse_string(raw_overrides)
	if typeof(parsed) == TYPE_DICTIONARY:
		keyboard_overrides = parsed


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "shake_scale", shake_scale)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "font_style", font_style)
	# autofire intentionally NOT saved — runtime-only, defaults off each launch.
	cfg.set_value("controls", "keyboard_overrides", JSON.stringify(keyboard_overrides))
	cfg.save(CFG_PATH)


# ---- Apply paths ----

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	_apply_audio()
	save_to_disk()
	settings_changed.emit()

func set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	_apply_audio()
	save_to_disk()
	settings_changed.emit()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	_apply_audio()
	save_to_disk()
	settings_changed.emit()

func set_shake_scale(v: float) -> void:
	shake_scale = clamp(v, 0.0, 1.0)
	save_to_disk()
	settings_changed.emit()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window()
	save_to_disk()
	settings_changed.emit()


func set_font_style(style: String) -> void:
	# Only "pixel" and "ttf" are valid. Anything else falls back to pixel.
	font_style = style if style == "ttf" else "pixel"
	_apply_font()
	save_to_disk()
	settings_changed.emit()


func _apply_font() -> void:
	UiTheme.apply_font_to_default_theme()


func set_autofire(on: bool) -> void:
	autofire = on
	# Runtime-only — do NOT persist. Fresh launch always starts off.
	settings_changed.emit()


# Persist + apply a keybind override. Replaces the action's first
# keyboard event with the given physical_keycode. Pass keycode = 0 to
# clear the override (restore project default).
func set_keybind(action_name: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action_name):
		return
	if physical_keycode == 0:
		keyboard_overrides.erase(action_name)
	else:
		keyboard_overrides[action_name] = physical_keycode
	_apply_keybind(action_name)
	save_to_disk()
	settings_changed.emit()


func _apply_keybinds() -> void:
	for action_name in keyboard_overrides.keys():
		_apply_keybind(action_name)


func _apply_keybind(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	if not keyboard_overrides.has(action_name):
		return
	var target_keycode: int = int(keyboard_overrides[action_name])
	# Erase the first existing keyboard event; replace with the override.
	var existing_key: InputEventKey = null
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			existing_key = ev
			break
	if existing_key:
		InputMap.action_erase_event(action_name, existing_key)
	var new_ev := InputEventKey.new()
	new_ev.physical_keycode = target_keycode
	new_ev.keycode = target_keycode
	InputMap.action_add_event(action_name, new_ev)


func _apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(max(master_volume, 0.0001)))
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(max(music_volume, 0.0001)))
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(max(sfx_volume, 0.0001)))


func _apply_window() -> void:
	# Cursor-offset bug ROOT CAUSE (diagnosed via the F9 overlay): the 1920x1080
	# WINDOWED window + title bar overflows a 1920x1080 screen, so Windows shrinks
	# the client to ~1920x1061 while content_scale stays 1920x1080 -> the content is
	# squished to 0.982 + pillarboxed (origin ~17), which desyncs the cursor mapping
	# (the offset was windowed-only; fullscreen at 1920x1080 == content maps 1:1 and
	# was always clean). FIX: window/size/borderless=true in project.godot removes
	# the title bar so the 1920x1080 client fits the screen exactly even windowed.
	# So plain borderless WINDOW_MODE_FULLSCREEN is fine again (and EXCLUSIVE made
	# alt-tab worse — reverted).
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
