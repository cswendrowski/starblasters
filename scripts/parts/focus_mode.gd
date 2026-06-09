extends "res://scripts/parts/mode_part.gd"

# Focus — the default Shift mode. Precision stance: 0.55x move speed, tight hitbox
# dot + cyan glow/trail, intangible-feel dodging, off a continuous seconds-reserve.
# The behavior already lives in player.gd (gated on active_mode == FOCUS); this part
# just declares the stance + occupies the slot so it can be swapped for Phase/Hyper.
# Design: docs/shift_mode_system_2026-06-08.md §3.1.


func _init() -> void:
	super._init()
	mode_id = Mode.FOCUS
	display_name = "Focus"
	description = "Precision stance: slow, tight hitbox, intangible-feel dodging on a recharging reserve. The default mode."
