extends Node

# Player primary-fire muzzle FX. Three ingredients (Roman, 2026-05-16):
#   1. Brief warm flash sprite at the muzzle (additive, ~80ms).
#   2. Gray smoke trail puffing back along the ship's travel path. The ship
#      conceptually flies UP through space, so smoke drifts DOWNWARD in
#      screen space.
#   3. A single tumbling shell casing ejected sideways with gravity, freed
#      when it leaves the screen.
#
# Usage:
#   const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
#   MuzzleFx.play(muzzle_world_pos)

const SHELL_TEX = preload("res://graphics/2x1-shell.png")
const ShellCasing = preload("res://scripts/effects/shell_casing.gd")
# Machinegun muzzle-flash strip (Cobalt 2026-05-21). 5 frames of 16×16;
# _spawn_flash picks a random frame each fire so consecutive shots don't
# look identical.
const MUZZLE_STRIP = preload("res://graphics/gun_muzzle_flash.png")
const MUZZLE_STRIP_HFRAMES := 5
# Default-blaster muzzle strip (Cobalt 2026-05-21). 3 frames of 16×16,
# cyan-blue glow color #5acbfd.
const BLASTER_MUZZLE_STRIP = preload("res://graphics/blaster_muzzle.png")
const BLASTER_MUZZLE_STRIP_HFRAMES := 3
const BLASTER_GLOW_COLOR := Color(0.353, 0.796, 0.992, 1.0)


static func play(world_pos: Vector2, host: Node = null) -> void:
	var root = Engine.get_main_loop().root
	# Flash parents under the host (player) when supplied so it inherits
	# the ship's transform and renders on the same canvas (the star_flash
	# beam windup uses this same pattern and renders correctly). Smoke +
	# shell stay at scene root since they outlive the player frame and
	# drift through world space.
	_spawn_flash(host if host != null else root, world_pos, host != null)
	_spawn_smoke(root, world_pos)
	_spawn_shell(root, world_pos)


# Energy Blaster muzzle FX — blue additive flash, no smoke, no shell. Used
# for the default Energy Blaster cannon (Roman, 2026-05-16). Replaces the
# warm/smokey machinegun look when the equipped CANNON is the blaster.
static func play_energy(world_pos: Vector2, host: Node = null) -> void:
	var root = Engine.get_main_loop().root
	var parent: Node = host if host != null else root
	var use_local: bool = host != null
	# Cobalt 2026-05-21: replace the gradient-only flash with the
	# blaster_muzzle strip + a cyan-blue glow halo at #5acbfd.
	# When `host` is supplied, parent under it so the flash inherits the
	# ship's transform (matches what star_flash does for the beam windup).
	var glow := Sprite2D.new()
	glow.texture = _build_flash_texture()
	glow.position = (Vector2(0, 0) if use_local else world_pos)
	if use_local:
		glow.position = world_pos - (host as Node2D).global_position
	glow.scale = Vector2(1.05, 1.05)
	glow.modulate = BLASTER_GLOW_COLOR
	glow.z_index = 4
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	parent.add_child(glow)
	var gtw := glow.create_tween()
	gtw.tween_property(glow, "scale", Vector2(1.8, 1.8), 0.15)
	gtw.parallel().tween_property(glow, "modulate:a", 0.0, 0.15)
	gtw.tween_callback(glow.queue_free)
	# Pixel-art strip — random frame per shot. Sprite held at 1.5× and
	# at full alpha for 70 ms so it reads in the GIF, then fades.
	var flash := Sprite2D.new()
	flash.texture = BLASTER_MUZZLE_STRIP
	flash.hframes = BLASTER_MUZZLE_STRIP_HFRAMES
	flash.frame = randi() % BLASTER_MUZZLE_STRIP_HFRAMES
	if use_local:
		flash.position = world_pos - (host as Node2D).global_position
	else:
		flash.position = world_pos
	flash.scale = Vector2(1.5, 1.5)
	flash.z_index = 5
	parent.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(flash, "modulate:a", 0.0, 0.10)
	tw.tween_callback(flash.queue_free)


static func _spawn_flash(parent: Node, world_pos: Vector2, use_local: bool = false) -> void:
	# Yellow-orange glow halo + random-frame strip. When `parent` is a
	# Node2D (host = player), the positions are local to the host so the
	# flash inherits the ship's transform/canvas. Falls back to world
	# position when `parent` is the scene root.
	#
	# Cobalt 2026-05-21 visibility pass: scale + lifetime bumped so the
	# flash reads clearly per shot. Sprite holds full alpha for the first
	# half of its life before fading, so it lingers visible across more
	# captured frames.
	var local_pos: Vector2 = world_pos
	if use_local and parent is Node2D:
		local_pos = world_pos - (parent as Node2D).global_position
	var glow := Sprite2D.new()
	glow.texture = _build_flash_texture()
	glow.position = local_pos
	glow.scale = Vector2(1.0, 1.0)
	glow.modulate = Color(1.0, 0.72, 0.28, 1.0)  # yellow-orange
	glow.z_index = 4
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	parent.add_child(glow)
	var glow_tw := glow.create_tween()
	glow_tw.tween_property(glow, "scale", Vector2(1.8, 1.8), 0.15)
	glow_tw.parallel().tween_property(glow, "modulate:a", 0.0, 0.15)
	glow_tw.tween_callback(glow.queue_free)
	var flash := Sprite2D.new()
	flash.texture = MUZZLE_STRIP
	flash.hframes = MUZZLE_STRIP_HFRAMES
	flash.frame = randi() % MUZZLE_STRIP_HFRAMES
	flash.position = local_pos
	flash.scale = Vector2(1.5, 1.5)
	flash.z_index = 5
	parent.add_child(flash)
	# Hold full alpha for the first 70 ms so the sprite reads even in a
	# 30fps GIF, then fade out across another 80 ms.
	var tw := flash.create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(flash, "modulate:a", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)


static func _spawn_smoke(root: Node, world_pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	# Spawn slightly behind the muzzle so the smoke trails away from the ship
	# in screen space (downward, since ship is flying up).
	p.position = world_pos + Vector2(0, 6)
	p.amount = 5
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.texture = _build_smoke_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	# Cobalt 2026-05-21: muzzle smoke shrunk to 50% — radius, velocity,
	# and scale all halved so the smoke reads as a small puff rather
	# than a billowing column.
	p.emission_sphere_radius = 2.0
	p.direction = Vector2(0, 1)  # downward = "back along ship's travel"
	p.spread = 28.0
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 80.0
	p.linear_accel_min = 15.0
	p.linear_accel_max = 25.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.75, 0.75, 0.78, 0.65),  # bright gray at puff
		Color(0.55, 0.55, 0.58, 0.45),
		Color(0.35, 0.35, 0.38, 0.0),   # fade to transparent dark gray
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	p.color_ramp = grad
	p.z_index = 3
	root.add_child(p)
	# CPUParticles2D doesn't auto-free; clean up shortly after lifetime ends.
	root.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)


static func _spawn_shell(root: Node, world_pos: Vector2) -> void:
	var shell := Sprite2D.new()
	shell.texture = SHELL_TEX
	# Half size of the prior pass (Roman). Native pixel scale.
	shell.scale = Vector2(1.0, 1.0)
	# Spawn further back along the ship body, still right side. The previous
	# spawn at world_pos + (6, 4) was at the muzzle tip; this puts the port
	# ~midship on the right.
	shell.position = world_pos + Vector2(10.0, 18.0)
	shell.z_index = 4
	shell.set_script(ShellCasing)
	root.add_child(shell)
	# Coast at warp-streak speed (~520 px/s downward) so shells sit in the
	# same motion frame as the parallax streaks. Small rightward kick from
	# the ejection port; the rest is the world streaming past the ship.
	var v := Vector2(randf_range(60.0, 90.0), randf_range(480.0, 560.0))
	shell.call_deferred("launch", v, 0.0)


# 32x32 soft white→transparent radial gradient. The flash sprite uses additive
# blending so this drives both shape and brightness.
static func _build_flash_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# 16x16 softer disc for smoke puffs — slightly chunkier falloff than the
# flash so individual puffs read as separate gray blobs rather than one
# continuous fog.
static func _build_smoke_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 16
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
