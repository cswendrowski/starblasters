extends "res://scripts/enemies/enemy_core.gd"

# Minelayer. Crosses the playfield (side_traverse pattern) dropping DUMB bomblets via a TIMER
# EmitterComponent + a DEATH-scatter emitter — both configured in the roster ("emitters" =
# MINELAYER_EMITTERS). The drop firing was bespoke (_process timer + explode scatter); migrated to
# the configured emitter system 2026-06-19. The only bespoke piece left is the SIDE-ENTRY spawn:
# the carrier enters from a side edge at the mid-upper band and crosses, not the standard top rig.


func _ready() -> void:
	# Crosses the screen and exits the opposite side; never opens a hull gun (it drops via emitters).
	offscreen_mode = OffscreenMode.FREE_OPPOSITE_SIDE
	shoot_pattern = null
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	super._ready()


# Side-entry override: spawn just off the corresponding edge at the mid-upper band (0.33) so the
# line of mines lands ahead of the player (Roman 2026-06-01), then cruise across. Direction comes
# from the side_traverse pattern (the wave generator sets it).
func start(pos: Vector2) -> void:
	super.start(pos)
	var dir: int = 1
	if _pattern != null and "direction" in _pattern:
		dir = int(_pattern.direction)
	var mid_y: float = screensize.y * 0.33
	if dir > 0:
		position = Vector2(Playfield.X_MIN - 32.0, mid_y)
	else:
		position = Vector2(Playfield.X_MAX + 32.0, mid_y)
