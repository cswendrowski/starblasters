extends "res://scripts/parts/smart_mount.gd"

# Blaster Smart Mount — auto-turrets your Blaster onto nearby enemies in a 120° front arc.
# You can still manually fire your equipped Primary; Q-swap to the blaster is disabled (it's
# automatic now). Mk raises traverse + tightens dispersion (see smart_mount.gd).


func _init() -> void:
	super._init()
	module_id = "blaster_smart_mount"
	display_name = "Blaster Smart Mount"
	description = "Auto-fires your Blaster at nearby enemies in a 120° front arc. You still fire your Primary yourself; Q-swap to the blaster is disabled. Mk speeds traverse + tightens aim."


func _is_blaster() -> bool:
	return true
