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
const GLOW_COLOR := Color(1.0, 0.95, 0.2)   # bright yellow diffuse glow


func _ready() -> void:
	var spr := $Core as AnimatedSprite2D
	if spr != null:
		spr.play("default")
		# Double brightness + size so firecores really pop (Roman 2026-06-07).
		GlowShaderFx.apply(spr, GLOW_COLOR, 2.0, 2.0)
	# NOTE: no engine trail here (Roman 2026-06-08). The decorative core sits at the
	# CENTER of every ship that carries one, so a trail off it gave every such enemy a
	# spurious central streak. The standalone firecore HAZARD gets its trail from an
	# Engine marker in its own scene instead.
