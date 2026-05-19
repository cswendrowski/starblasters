extends ParallaxBackground
func _process(delta):
	scroll_base_offset -= Vector2(0,-40) * delta
