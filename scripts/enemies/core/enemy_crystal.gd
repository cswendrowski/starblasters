extends "res://scripts/enemy_core.gd"

# Crystal (Roman 2026-05-24; on-lane migration 2026-06-08). Was a bespoke 6-phase state machine;
# now on the lane system. The Pendulum movement pattern owns the dual-band dive→fishtail-aim→fire
# →rise→aim→fire→(50/50) repeat/exit choreography AND the rotation (the fishtail aim). The host's
# spread weapon (spread5 from the roster) fires once at each stop via fire_on_phase. The matrix
# assigns the "pendulum" movement; nothing else here is bespoke.
#
# auto_rotate is off so the pattern's aim controls rotation; recycle_passes 0 so the EXIT phase
# frees it for good (no parallax fly-back).

func _ready() -> void:
	auto_rotate = false
	fire_on_phase = "fire"
	recycle_passes = 0
	super._ready()
