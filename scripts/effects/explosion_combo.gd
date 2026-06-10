extends Node2D

# Two-stage explosion (Roman 2026-06-10): opens with the small-circle blast,
# then the full default explosion lands on top as it peaks — a quick spark that
# blooms into a big boom. Used as the "small_then_default" ExplosionFx variant.
#
# Both sub-explosions are spawned at this node's origin (so ExplosionFx.play's
# global_position carries through) at native 1× scale. This node frees itself
# once both have finished.

const SMALL_SCENE := preload("res://scenes/effects/explosion_small_circle.tscn")
const DEFAULT_SCENE := preload("res://scenes/effects/explosion.tscn")

# ExplosionFx.play sets these if present.
@export var base_scale: float = 1.0
@export var emit_light: bool = true

# Delay before the big default boom — short enough that the small circle is
# still flashing when it lands, so the two read as one building blast.
@export var stage_gap: float = 0.2


func _ready() -> void:
	_spawn(SMALL_SCENE)
	get_tree().create_timer(stage_gap).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_spawn(DEFAULT_SCENE))
	# Outlive both sub-explosions (each self-frees ~0.75s), then clean up.
	get_tree().create_timer(stage_gap + 1.0).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())


func _spawn(scene: PackedScene) -> void:
	var e: Node2D = scene.instantiate()
	if "base_scale" in e:
		e.base_scale = base_scale
	if "emit_light" in e:
		e.emit_light = emit_light
	add_child(e)
