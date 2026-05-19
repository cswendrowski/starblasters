extends SceneTree

# Spike: does a Control with PRESET_FULL_RECT under a CanvasLayer with
# scale=0.5 resolve to (480,270) or (960,540) in local coords?
# Answer determines whether the "option B" UI migration can use anchors
# normally or must size everything explicitly in 960×540 coords.

func _init() -> void:
	var canvas := CanvasLayer.new()
	canvas.transform = Transform2D().scaled(Vector2(0.5, 0.5))
	root.add_child(canvas)
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(c)
	# Force a layout pass.
	await process_frame
	await process_frame
	print("viewport size: ", root.size)
	print("control size : ", c.size)
	print("control pos  : ", c.position)
	quit()
