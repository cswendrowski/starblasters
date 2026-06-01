extends CanvasLayer
# Wave banner: fades in, holds, fades out, frees. Was previously holo-shaded
# with jittery onset/offset; stripped 2026-05-16 (Roman: "clean UI setup").

@onready var label: Label = $Center/Label

const FADE_IN := 0.45
const HOLD := 0.85
const FADE_OUT := 0.55


func _ready() -> void:
	if label:
		label.modulate.a = 0.0
	visible = false


func show_text(custom_text: String) -> void:
	if label == null:
		return
	_animate(custom_text)


func show_wave(wave_index: int, total: int) -> void:
	if label == null:
		return
	_animate("WAVE %d / %d" % [wave_index + 1, total])


func _animate(text: String) -> void:
	if label == null:
		return
	label.text = text
	visible = true
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_property(label, "modulate:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.finished.connect(queue_free)
