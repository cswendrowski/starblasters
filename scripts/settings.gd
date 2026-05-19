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
# Screen shake intensity multiplier (0 disables shake entirely; 1 = stock).
var shake_scale: float = 1.0
# Fullscreen window mode (false = windowed, the project default).
var fullscreen: bool = false
# Font face: "pixel" = Pixel Operator (default, designed for small sizes),
# "ttf" = Pixelify Sans (smoother TTF alternative). Toggled in the
# Options menu; saved on change.
var font_style: String = "pixel"


func _ready() -> void:
	load_from_disk()
	_apply_audio()
	_apply_window()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	music_volume = float(cfg.get_value("audio", "music_volume", music_volume))
	shake_scale = float(cfg.get_value("video", "shake_scale", shake_scale))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	font_style = String(cfg.get_value("video", "font_style", font_style))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("video", "shake_scale", shake_scale)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "font_style", font_style)
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
	save_to_disk()
	settings_changed.emit()


func _apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(max(master_volume, 0.0001)))
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(max(music_volume, 0.0001)))


func _apply_window() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
