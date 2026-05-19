extends SceneTree

func _initialize() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 12345
	print("rng1 seed=12345: ", rng1.randi() % 100, " ", rng1.randi() % 100, " ", rng1.randi() % 100)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	print("rng2 seed=12345: ", rng2.randi() % 100, " ", rng2.randi() % 100, " ", rng2.randi() % 100)

	# Same seed via reassignment.
	rng1.seed = 12345
	print("rng1 reseeded:   ", rng1.randi() % 100, " ", rng1.randi() % 100, " ", rng1.randi() % 100)

	# state vs seed
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 12345
	print("rng3 fresh state=", rng3.state)
	rng3.randi()
	print("rng3 after 1 call state=", rng3.state)
	rng3.seed = 12345
	print("rng3 reseeded state=", rng3.state)
	quit()
