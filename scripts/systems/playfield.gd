class_name Playfield
extends Object

# 480×270 widescreen rework, phase 2 (Roman, 2026-05-19):
# Gameplay is constrained to a 216×270 vertical band centred in the
# 480-wide viewport — same aspect ratio as the original 320×400
# (0.8 : 1) so wave generators and movement patterns authored against
# the legacy playfield read correctly. The left + right side bands
# (132 px each) are reserved for future side-HUD / parallax framing.
#
# Use these constants in place of `get_viewport_rect().size.x` when
# you need the gameplay bound (spawning, wall-detection, clamping the
# player). Everything that should respect screen edges (backdrop,
# despawn margins) still reads from the viewport directly.

const W: float = 216.0
const H: float = 270.0
const X_MIN: float = 132.0
const X_MAX: float = 348.0  # X_MIN + W
const Y_MIN: float = 0.0
const Y_MAX: float = 270.0
const CENTER := Vector2(240.0, 135.0)


static func clamp_pos(p: Vector2, inset: float = 0.0) -> Vector2:
	return Vector2(
		clamp(p.x, X_MIN + inset, X_MAX - inset),
		clamp(p.y, Y_MIN + inset, Y_MAX - inset)
	)
