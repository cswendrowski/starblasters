extends Node

# Centralized dev/debug flags. Autoloaded as "Dbg".
# Anything gated on Dbg.is_dev is automatically off in release builds
# (because OS.is_debug_build() is false when exported via --export-release).

# True when running from the editor or in a debug export.
@onready var is_dev: bool = OS.is_debug_build()

# Individual dev shortcuts. Add new flags here as needed.
# All default to is_dev so they're off automatically in release.
@onready var boss_anywhere: bool = is_dev       # Boss nodes always clickable on sector map
@onready var god_mode: bool = false             # Player can't die (set true to test bosses)
@onready var skip_intro: bool = false           # Skip the sector intro card
@onready var start_bounty: int = 0              # Spawn with this much bounty for shop testing

func _ready() -> void:
	if is_dev:
		print("[Dbg] running in dev/editor build — dev shortcuts active")
