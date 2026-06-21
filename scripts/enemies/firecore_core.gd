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

# HDR-bright yellow — R/G must clear the env glow_hdr_threshold (1.5) to bloom.
# Hue-preserving boost of the old (1.0, 0.95, 0.2) ember color. Tune to taste.
const GLOW_HDR := Color(1.9, 1.8, 0.38, 1.0)


func _ready() -> void:
	var spr := $Core as AnimatedSprite2D
	if spr != null:
		spr.play("default")
		# HDR modulate → env bloom does the glow (replaces GlowShaderFx, Roman 2026-06-20).
		spr.modulate = GLOW_HDR
	# NOTE: no engine trail here (Roman 2026-06-08). The decorative core sits at the
	# CENTER of every ship that carries one, so a trail off it gave every such enemy a
	# spurious central streak. The standalone firecore HAZARD gets its trail from an
	# Engine marker in its own scene instead.
