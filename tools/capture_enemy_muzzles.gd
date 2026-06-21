extends SceneTree

# Captures enemy muzzle-marker firing + pink muzzle flash (Roman 2026-05-31).
# Spawns three shooters side by side and drives their real fire path directly
# (enemy_core gates firing on ShootTimer + _on_playfield(), and skirmisher/
# hover fire on movement phases, so a naive instantiate-and-wait may never
# fire in-window — we call fire() ourselves on a cadence):
#   - drifter    (single Muzzle, single_shot)      → one flash per shot
#   - skirmisher (cannon_left/right, aimed_fire)    → ALTERNATES L/R
#   - hover      (single Muzzle, pair_shot)         → PAIR (2 bullets) per shot
# Verifies: bullets emit from the marker pixels, the pink flash anchors at
# each muzzle base and rotates to the shot direction, two-muzzle alternation,
# hover pairs.

const OUT_DIR := "res://captures/frames_enemy_muzzles"
const FPS: int = 30
const DURATION: float = 4.0
const FRAME_TIME: float = 1.0 / float(FPS)

const DART := preload("res://scenes/enemies/factions/privateer/enemy_dart.tscn")
const SKIRMISHER := preload("res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn")
const GUNNER := preload("res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn")


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


func _spawn(scene: PackedScene, pos: Vector2) -> Node2D:
	var e: Node2D = scene.instantiate()
	root.add_child(e)
	# enemy_core's start() kicks off entry tweens; we want a stationary shooter
	# parked on the playfield, so set position directly and arm nothing.
	e.global_position = pos
	return e


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Three shooters across the playfield band (X 132–348), upper third.
	var dart := _spawn(DART, Vector2(170, 70))
	var skirmisher := _spawn(SKIRMISHER, Vector2(240, 70))
	var gunner := _spawn(GUNNER, Vector2(310, 70))

	# Dummy player in the line of fire so aimed_fire has a target.
	var dummy := Area2D.new()
	dummy.global_position = Vector2(240, 230)
	dummy.add_to_group("player")
	root.add_child(dummy)

	# Let markers resolve their global_position.
	await create_timer(0.1).timeout

	var total: int = int(DURATION * float(FPS))
	# Fire cadence: every ~0.3s (every 9 frames) so flashes are visible and
	# alternation/pairs read across the GIF.
	var fire_every: int = 9
	for f in total:
		if f % fire_every == 0:
			_fire(dart)
			_fire(skirmisher)
			_fire(gunner)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[enemy-muzzles] captured %d frames" % total)
	quit()


func _fire(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	# Pattern enemies (drifter/skirmisher/hover) expose shoot_pattern; call its
	# real fire() so _spawn_bullet → muzzle + flash runs exactly as in-game.
	if "shoot_pattern" in enemy and enemy.shoot_pattern != null:
		enemy.shoot_pattern.fire(enemy)
