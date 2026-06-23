extends Node2D

# Decorative zealot firecore (M6c, Roman 2026-06-07). A pulsing yellow ember
# placed inside a zealot ship's scene as a visual "core" — purely cosmetic: no
# collision, no behavior, not a hazard (that's firecore_hazard.tscn, the dropped
# version). Glows via HDR-bright modulate + the WorldEnvironment bloom.
#
# GLOW (Roman 2026-06-20): the old per-sprite GlowShaderFx halo predated the
# WorldEnvironment bloom and now double-bloomed with it into a blurry blob. We
# drop it and instead push the ember past the env's glow_hdr_threshold (1.5) so
# the scene bloom glows it natively — sharp core, no upscaled halo quad. The
# WRAPPER (this Node2D whose child "Core" is the sprite) is retained as the
# existing authored scene structure; author it under the hull (z_index -1).

# Firecores share the "engines" HDR-glow multiplier (Roman 2026-06-22) so they bloom via the env.
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")


func _ready() -> void:
	var spr := $Core as AnimatedSprite2D
	if spr != null:
		spr.play("default")
		# HDR modulate → env bloom does the glow (uses the tuned "engines" multiplier).
		spr.modulate = VfxGlow.prod_hdr("engines")
	# NOTE: no engine trail here (Roman 2026-06-08). The decorative core sits at the
	# CENTER of every ship that carries one, so a trail off it gave every such enemy a
	# spurious central streak. The standalone firecore HAZARD gets its trail from an
	# Engine marker in its own scene instead.
