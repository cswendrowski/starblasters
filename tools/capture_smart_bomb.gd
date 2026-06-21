extends SceneTree

# Capture the Smart Bomb shockwave mechanic: flashes player white, spawns an
# expanding radial wave that ignores shields, one-shots large non-tough enemies,
# kills shielded enemies, and damages tough/huge survivors. ~2.0s total.
#
# Spawn config: 1 player + 5-6 enemies at varied positions + 4 enemy bullets.
# Timeline: 0.3s calm, then activate bomb, wave expands + resolves.

const OUT_DIR := "res://captures/smart_bomb"
const FPS: int = 30
const DURATION: float = 2.0
const FRAME_TIME: float = 1.0 / float(FPS)

# Enemy scenes: small, medium, large non-tough, large tough, shielded chaff.
const SMALL_ENEMY := "res://scenes/enemies/factions/privateer/enemy_dart.tscn"
const MEDIUM_ENEMY := "res://scenes/enemies/core/enemy_bomb_drone.tscn"
const LARGE_ENEMY := "res://scenes/enemies/core/enemy_cruiser.tscn"
const TOUGH_ENEMY := "res://scenes/enemies/factions/corporate/enemy_bulwark.tscn"
const CHAFF_SHIELDED := "res://scenes/enemies/factions/privateer/enemy_dart.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BULLET_SCENE := "res://scenes/projectiles/enemy_bullet.tscn"

var _enemies: Array = []
var _bullets: Array = []
var _bomb_activated := false


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _run() -> void:
	# Background.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.size = Vector2(480, 270)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -5
	bg_layer.add_child(bg)
	root.add_child(bg_layer)

	# Camera.
	var cam := Camera2D.new()
	cam.position = Vector2(240, 135)
	root.add_child(cam)
	cam.make_current()

	# Player.
	var player: Node2D = PLAYER_SCENE.instantiate()
	player.position = Vector2(240, 230)
	root.add_child(player)
	await create_timer(0.1).timeout
	if "controls_enabled" in player:
		player.controls_enabled = false

	# Spawn enemies with deterministic positions.
	var enemy_configs := [
		{"scene": SMALL_ENEMY, "pos": Vector2(140, 60), "name": "Small (4 HP)"},
		{"scene": MEDIUM_ENEMY, "pos": Vector2(240, 50), "name": "Medium (8 HP)"},
		{"scene": LARGE_ENEMY, "pos": Vector2(300, 80), "name": "Large Non-Tough (16 HP)"},
		{"scene": TOUGH_ENEMY, "pos": Vector2(180, 140), "name": "Tough Large (32 HP)"},
		{"scene": CHAFF_SHIELDED, "pos": Vector2(320, 130), "name": "Shielded Chaff (4 HP + shield)"},
	]

	for cfg in enemy_configs:
		var scene = load(cfg["scene"]) as PackedScene
		if not scene:
			print("[smart-bomb] failed to load %s" % cfg["scene"])
			continue
		var e = scene.instantiate()
		e.position = cfg["pos"]
		root.add_child(e)
		e.add_to_group("enemies")

		# Wait for _ready to complete.
		await create_timer(0.05).timeout

		# Set predictable HP and add shield if needed.
		if cfg["name"].find("Tough") != -1:
			# Tough: set to 32 HP.
			if "max_health" in e:
				e.max_health = 32
				e.health = 32
			elif "max_hull" in e:
				e.max_hull = 32
				e.hull = 32
		elif cfg["name"].find("Large Non") != -1:
			# Large non-tough: 16 HP (dies to Mk.1 bomb).
			if "max_health" in e:
				e.max_health = 16
				e.health = 16
			elif "max_hull" in e:
				e.max_hull = 16
				e.hull = 16
		elif cfg["name"].find("Medium") != -1:
			# Medium: 8 HP.
			if "max_health" in e:
				e.max_health = 8
				e.health = 8
			elif "max_hull" in e:
				e.max_hull = 8
				e.hull = 8
		elif cfg["name"].find("Small") != -1:
			# Small: 4 HP.
			if "max_health" in e:
				e.max_health = 4
				e.health = 4
			elif "max_hull" in e:
				e.max_hull = 4
				e.hull = 4

		# Add shield to the shielded chaff.
		if cfg["name"].find("Shielded") != -1:
			if "shield" in e:
				e.shield = 1

		_enemies.append({"node": e, "name": cfg["name"]})
		print("[smart-bomb] spawned %s at %s" % [cfg["name"], cfg["pos"]])

	# Spawn 4 enemy bullets for the wave to clear.
	var bullet_positions := [
		Vector2(160, 100),
		Vector2(280, 90),
		Vector2(200, 150),
		Vector2(320, 140),
	]
	for bpos in bullet_positions:
		var bscene = load(BULLET_SCENE) as PackedScene
		if not bscene:
			continue
		var b = bscene.instantiate()
		b.position = bpos
		root.add_child(b)
		b.add_to_group("bullets")
		_bullets.append(b)
	print("[smart-bomb] spawned %d bullets" % _bullets.size())

	# Print enemy state before bomb.
	print("\n--- PRE-BOMB STATE ---")
	for cfg in _enemies:
		var e = cfg["node"]
		var hp_field = "health" if "health" in e else "hull" if "hull" in e else "unknown"
		var hp_val = e.get(hp_field, "?")
		print("[smart-bomb] BEFORE: %s => %s=%s (alive=%s)" % [cfg["name"], hp_field, hp_val, is_instance_valid(e)])

	# Let the scene settle for 0.3s.
	await create_timer(0.3).timeout

	# Activate Smart Bomb at t=0.3s.
	var SmartBombScript = preload("res://scripts/parts/smart_bomb.gd")
	var bomb = SmartBombScript.new()
	bomb.mark = 1  # Mk.1 => 18 damage.
	bomb.activate(player)
	_bomb_activated = true
	print("\n[smart-bomb] BOMB ACTIVATED at t=0.3s")

	# Capture frames through the wave expansion + exit.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))

	# Print final enemy state.
	print("\n--- POST-BOMB STATE ---")
	var passed := 0
	var failed := 0
	for cfg in _enemies:
		var e = cfg["node"]
		var alive: bool = is_instance_valid(e)
		var hp_field: String = "health" if "health" in e else "hull" if "hull" in e else "unknown"
		var hp_val = e.get(hp_field, "?") if alive else "DEAD"

		var expected_alive: bool = cfg["name"].find("Tough") != -1
		var result = "ALIVE" if alive else "DEAD"
		var status = "PASS" if (alive == expected_alive) else "FAIL"

		print("[smart-bomb] AFTER: %s => %s (actual=%s, expected=%s) [%s]" % [
			cfg["name"], result, result, "ALIVE" if expected_alive else "DEAD", status
		])

		if status == "PASS":
			passed += 1
		else:
			failed += 1

	# Print bullet cancellation check.
	var bullets_cancelled = 0
	for b in _bullets:
		if not is_instance_valid(b):
			bullets_cancelled += 1
	print("\n[smart-bomb] bullets cancelled: %d / %d" % [bullets_cancelled, _bullets.size()])

	print("\n--- SUMMARY ---")
	print("[smart-bomb] enemy kills: %d / 4 (expected) [%s]" % [passed, "PASS" if passed == 4 else "FAIL"])
	print("[smart-bomb] tough survivor: %d / 1 (expected) [%s]" % [failed, "PASS" if failed == 1 else "FAIL"])
	print("[smart-bomb] captured %d frames to %s" % [frame_count, OUT_DIR])

	quit()
