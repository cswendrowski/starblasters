extends Node2D

#func _on_timer_timeout():
#	queue_free()

func _on_shell_eject_particle_finished():
	queue_free()
