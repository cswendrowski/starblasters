extends SceneTree

# Captures the Sapper enemy in action:
# 0.0–2.0s: SEEKING (movement around top half, no beam)
# 2.0–8.0s: DRAINING (beam connects to player, shield drains)
# Shows omni-thrust movement pattern + teal drain beam + shield ring on sapper.
# Change 2: beam pulse animation visible in the drain phase.
# Change 3: sapper shield ring visible until shields break.

const OUT_DIR := "res://captures/sapper"
const FPS: int = 30
const DURATION: float = 8.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SAPPER_SCENE := preload("res://scenes/enemies/enemy_sapper.tscn")


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
	# Black background (480×270)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Spawn Sapper at settle position (y=60)
	var enemy: Node2D = SAPPER_SCENE.instantiate()
	enemy.position = Vector2(240, 60)
	root.add_child(enemy)

	# Create a dummy player node in the "player" group.
	# Needs: shield (int, with setter emitting shield_changed), max_shield,
	# ShieldRegenTimer child, and a Ship child for the hit-flash.
	var dummy_player := Node2D.new()
	dummy_player.name = "DummyPlayer"
	dummy_player.global_position = Vector2(240, 200)
	dummy_player.add_to_group("player")

	# Script that mirrors the parts of player.gd the sapper touches.
	var player_script = GDScript.new()
	player_script.source_code = """
extends Node2D

signal shield_changed(max_val, val)

var max_shield: int = 3
var shield: int = 3:
	set(v):
		shield = clampi(v, 0, max_shield)
		shield_changed.emit(max_shield, shield)

func take_damage(_amount: int) -> void:
	pass
"""
	dummy_player.set_script(player_script)

	# ShieldRegenTimer child.
	var regen_timer := Timer.new()
	regen_timer.name = "ShieldRegenTimer"
	regen_timer.wait_time = 3.0
	dummy_player.add_child(regen_timer)

	# Ship child — needed so hit_flash_fx.flash can find it.
	var ship_node := Node2D.new()
	ship_node.name = "Ship"
	dummy_player.add_child(ship_node)

	root.add_child(dummy_player)

	# Draw a simple blue rectangle at the dummy player position so the beam
	# target is visible in the frames.
	var player_visual := ColorRect.new()
	player_visual.color = Color(0.3, 0.5, 1.0, 0.8)
	player_visual.size = Vector2(16, 12)
	player_visual.position = dummy_player.global_position - player_visual.size * 0.5
	root.add_child(player_visual)

	# Wait a frame for initialization
	await create_timer(0.05).timeout

	# Capture 8 seconds at 30fps = 240 frames
	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[sapper] captured %d frames" % total)
	quit()
