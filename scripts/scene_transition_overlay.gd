extends CanvasLayer

# Internal node script for scenes/effects/scene_transition.tscn.
# Exposes the overlay ColorRect's ShaderMaterial so the SceneTransition
# helper (scripts/scene_transition.gd) can tween its `progress` uniform.

@onready var overlay: ColorRect = $Overlay

func set_progress(value: float) -> void:
	if overlay == null:
		return
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", value)

func randomize_seed() -> void:
	if overlay == null:
		return
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("seed", randf() * 1000.0)
