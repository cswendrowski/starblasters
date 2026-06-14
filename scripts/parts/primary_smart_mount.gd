extends "res://scripts/parts/smart_mount.gd"

# Primary Smart Mount — auto-turrets your Primary onto nearby enemies in a 120° front arc.
# You can still manually fire your Blaster; Q-swap to the primary is disabled. If the
# Primary is a regen-ammo laser, the turret waits for a FULL recharge before firing the
# next magazine. Mk raises traverse + tightens dispersion (see smart_mount.gd).


func _init() -> void:
	super._init()
	module_id = "primary_smart_mount"
	display_name = "Primary Smart Mount"
	description = "Auto-fires your Primary at nearby enemies in a 120° front arc. You still fire your Blaster yourself; Q-swap to the primary is disabled. Regen lasers wait for a full recharge between bursts. Mk speeds traverse + tightens aim."


func _is_blaster() -> bool:
	return false
