extends Node2D

# Decorative zealot firecore (M6c, Roman 2026-06-07). A pulsing yellow ember
# placed inside a zealot ship's scene as a visual "core" — purely cosmetic: no
# collision, no behavior, not a hazard (that's firecore_hazard.tscn, the dropped
# version). Self-applies the shared yellow glow halo.
#
# This is a WRAPPER Node2D whose child "Core" AnimatedSprite2D is the ember: the
# glow halo must attach to the host sprite's PARENT, so the host has to be a child
# (then the halo lands on THIS wrapper, added during our own _ready — safe). Applying
# the glow directly to a top-level node would try to add the halo to the busy parent
# scene mid-instantiation and fail. Author the wrapper under the hull (z_index -1).

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
const GLOW_COLOR := Color(1.0, 0.95, 0.2)   # bright yellow diffuse glow


func _ready() -> void:
	var spr := $Core as AnimatedSprite2D
	if spr != null:
		spr.play("default")
		# Double brightness + size so firecores really pop (Roman 2026-06-07).
		GlowShaderFx.apply(spr, GLOW_COLOR, 2.0, 2.0)
	# Yellow engine trail off the core so it streaks as the enemy moves.
	var trail = EngineTrailFx.new()
	add_child(trail)
	trail.setup(self, [self])
