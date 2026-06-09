extends "res://scripts/enemy_core.gd"

# Crystal (Roman 2026-05-24; on-lane migration 2026-06-08; generic-pattern 2026-06-09). On the
# lane system: it HONORS whatever movement the matrix assigns (loiter_high/mid, etc.) rather than
# being locked to one pattern. Firing is the standard ShootTimer cadence so it shoots under ANY
# movement — the old `fire_on_phase = "fire"` only fired on the Pendulum's stop beats, so the
# crystal went silent the moment it was assigned anything but pendulum (Roman 2026-06-09).
#
# auto_rotate stays off (it's a facing-down holder; loiter manages its own facing during the
# hold); recycle_passes 0 so the EXIT phase frees it for good (no parallax fly-back).

func _ready() -> void:
	auto_rotate = false
	recycle_passes = 0
	super._ready()
