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

const SHELL_TEX = preload("res://graphics/2x1-shell.png")        # small casing (minigun)
const SHELL_TEX_LARGE = preload("res://graphics/3x1-shell.png")  # large casing (autocannon / machinegun)
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
# Rotary Laser muzzle-flash strip. Frame 0 is the projectile itself;
# frames 1–3 are the muzzle flash frames used here.
const ROTARY_LASER_STRIP = preload("res://graphics/energy_muzzle_blue.png")
const ROTARY_LASER_STRIP_HFRAMES := 4
const ROTARY_LASER_GLOW_COLOR := Color(0.3, 0.7, 1.0, 1.0)
# Enemy muzzle-flash strip (Roman 2026-05-31). 48×16 = 3 frames of 16×16,
# pink flame. The flame points UP (tip up, base at bottom) at rest.
const ENEMY_MUZZLE_STRIP = preload("res://graphics/projectiles/enemy_muzzle.png")
const ENEMY_MUZZLE_STRIP_HFRAMES := 3


static func play(world_pos: Vector2, host: Node = null) -> void:
	var root = Engine.get_main_loop().root
	# Smoke + shell must outlive the player frame, so they parent to the host's
	# CONTAINER (not the host itself) rather than the window root — that keeps
	# them in the player's coordinate space (the hangar runs the player inside a
	# SubViewport world; window-root parenting put the puffs in the top-left
	# corner). In combat the host's parent is the main scene, identical space to
	# the old root parenting. Flash parents under the host (local) as before.
	var fx_root: Node = root
	if host != null and host.get_parent() != null:
		fx_root = host.get_parent()
	_spawn_flash(host if host != null else root, world_pos, host != null)
	_spawn_smoke(fx_root, world_pos)
	_spawn_shell(fx_root, world_pos)


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
	flash.scale = Vector2(1.0, 1.0)  # Cobalt 2026-05-21: pixel-perfect 1×
	flash.z_index = 5
	parent.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(flash, "modulate:a", 0.0, 0.10)
	tw.tween_callback(flash.queue_free)


# Rotary Laser muzzle FX — cyan-blue additive glow + random flash frame
# drawn from frames 1–3 of the energy_laser_blue strip (frame 0 is the
# bullet projectile). Pattern mirrors play_energy().
static func play_rotary_laser(world_pos: Vector2, host: Node = null) -> void:
	var root = Engine.get_main_loop().root
	var parent: Node = host if host != null else root
	var use_local: bool = host != null
	# Cyan-blue additive glow halo.
	var glow := Sprite2D.new()
	glow.texture = _build_flash_texture()
	if use_local:
		glow.position = world_pos - (host as Node2D).global_position
	else:
		glow.position = world_pos
	glow.scale = Vector2(0.8, 0.8)
	glow.modulate = ROTARY_LASER_GLOW_COLOR
	glow.z_index = 4
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	parent.add_child(glow)
	var gtw := glow.create_tween()
	gtw.tween_property(glow, "scale", Vector2(1.4, 1.4), 0.08)
	gtw.parallel().tween_property(glow, "modulate:a", 0.0, 0.08)
	gtw.tween_callback(glow.queue_free)
	# Pixel-art flash — pick from frames 1..3 so the bullet frame (0) is
	# never shown as a flash.
	var flash := Sprite2D.new()
	flash.texture = ROTARY_LASER_STRIP
	flash.hframes = ROTARY_LASER_STRIP_HFRAMES
	flash.frame = randi() % ROTARY_LASER_STRIP_HFRAMES
	if use_local:
		flash.position = world_pos - (host as Node2D).global_position
	else:
		flash.position = world_pos
	flash.scale = Vector2(1.0, 1.0)
	flash.z_index = 5
	parent.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_interval(0.04)
	tw.tween_property(flash, "modulate:a", 0.0, 0.04)
	tw.tween_callback(flash.queue_free)


# Enemy muzzle flash (Roman 2026-05-31). Pink flame anchored at its BASE to
# `world_pos`, pointing along `dir`. No smoke, no shell (player-only). Always
# parented at ROOT in WORLD space — most enemies have auto_rotate=true, so
# parenting under them would double-rotate the flash and contaminate its
# angle with the enemy's banking. An ~80 ms flash needn't follow the enemy.
static func play_enemy(world_pos: Vector2, dir: Vector2, root: Node) -> void:
	if root == null:
		root = Engine.get_main_loop().root
	var flash := Sprite2D.new()
	flash.texture = ENEMY_MUZZLE_STRIP
	flash.hframes = ENEMY_MUZZLE_STRIP_HFRAMES
	# Random frame per shot so consecutive flashes differ.
	flash.frame = randi() % ENEMY_MUZZLE_STRIP_HFRAMES
	# Anchor the BASE (bottom-center) of the 16×16 frame at the node origin:
	# centered=true puts the frame center at origin, so shift it up by half a
	# frame (8 px) — the flame's bottom edge now sits on the origin and the
	# flame extends "up" (-Y) from there before rotation.
	flash.centered = true
	flash.offset = Vector2(0, -8)
	flash.global_position = world_pos
	# Sprite flame points up (-Y) at rest. atan2(dir) gives 0 = +X (east);
	# +PI/2 maps "up" to the fire direction so the flame extends along `dir`.
	flash.global_rotation = dir.angle() + PI * 0.5
	flash.z_index = 5
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	root.add_child(flash)
	# Match the player flash feel: hold full alpha ~70 ms, fade ~80 ms.
	var tw := flash.create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(flash, "modulate:a", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)


const GlowFxM = preload("res://scripts/effects/glow_shader_fx.gd")


# Unified player muzzle flash (Roman 2026-06-09 player pass): the flash strip is BOTTOM-anchored to
# the muzzle marker (its base sits on the marker, extends forward), tinted `color` with a matching
# DIFFUSE glow, rendered ABOVE the bullets (which now render under the ship), and it lasts ~a frame.
# `with_smoke_shell` adds the machinegun smoke + shell casing.
static func play_player(world_pos: Vector2, host: Node, color: Color, with_smoke_shell: bool = false, large_shell: bool = false) -> void:
	var parent: Node = host if host != null else Engine.get_main_loop().root
	var local_pos: Vector2 = world_pos
	if host != null and host is Node2D:
		local_pos = world_pos - (host as Node2D).global_position
	# Bottom-anchor: shift the centred 16px flash up by 8 so its bottom edge sits on the marker.
	local_pos += Vector2(0, -8)
	var flash := Sprite2D.new()
	flash.texture = MUZZLE_STRIP
	flash.hframes = MUZZLE_STRIP_HFRAMES
	flash.frame = randi() % MUZZLE_STRIP_HFRAMES
	flash.position = local_pos
	flash.modulate = color
	flash.z_index = 6   # above the player bullets (they render at z -1) + the ship
	var fmat := CanvasItemMaterial.new()
	fmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = fmat
	parent.add_child(flash)
	# Diffuse glow in the same colour (its own sibling node — free it with the flash).
	var glow: CanvasItem = GlowFxM.apply(flash, color)
	# Last ~a frame, then gone (no lingering fade).
	var tw := flash.create_tween()
	tw.tween_interval(0.045)
	tw.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free()
		if glow != null and is_instance_valid(glow):
			glow.queue_free())
	if with_smoke_shell:
		var fx_root: Node = host.get_parent() if (host != null and host.get_parent() != null) else Engine.get_main_loop().root
		_spawn_smoke(fx_root, world_pos)
		_spawn_shell(fx_root, world_pos, large_shell)


# Minigun ejection (Roman 2026-06-11): a single brass-coloured PIXEL flicked out the
# right side (with slight per-shot colour variation), trailing a thin 1px wisp of gun
# smoke. Replaces the shell casing + smoke puff for the minigun's rapid bullet hose.
static func eject_brass(parent: Node, world_pos: Vector2) -> void:
	if parent == null:
		return
	var px := Sprite2D.new()
	px.texture = _solid_pixel_texture(1)   # 1px source; ShellCasing scales it 2×→1× as it falls
	px.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Brass with per-shot colour variation.
	px.modulate = Color(randf_range(0.72, 0.92), randf_range(0.52, 0.70), randf_range(0.12, 0.30), 1.0)
	px.position = world_pos   # caller passes the ship's casing-eject marker position
	px.z_index = 4
	px.set_script(ShellCasing)
	parent.add_child(px)
	# Thin trailing gun-smoke wisp (1px particles, world-space → leaves a trail).
	var trail := CPUParticles2D.new()
	trail.amount = 6
	trail.lifetime = 0.3
	trail.local_coords = false
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	trail.direction = Vector2(0, -1)
	trail.spread = 18.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 3.0
	trail.initial_velocity_max = 9.0
	trail.scale_amount_min = 1.0
	trail.scale_amount_max = 1.0
	trail.texture = _solid_pixel_texture(1)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.6, 0.6, 0.62, 0.45), Color(0.4, 0.4, 0.42, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	trail.color_ramp = grad
	px.add_child(trail)
	# Out the right side + falling; small tumble.
	var v := Vector2(randf_range(40.0, 70.0), randf_range(120.0, 200.0))
	px.call_deferred("launch", v, randf_range(-8.0, 8.0))


# Cached solid-white square ImageTexture of `sz`×`sz` px (tint via modulate).
static var _pixel_tex_cache: Dictionary = {}
static func _solid_pixel_texture(sz: int) -> Texture2D:
	if _pixel_tex_cache.has(sz):
		return _pixel_tex_cache[sz]
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var t := ImageTexture.create_from_image(img)
	_pixel_tex_cache[sz] = t
	return t


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
	flash.scale = Vector2(1.0, 1.0)  # Cobalt 2026-05-21: pixel-perfect 1×
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


static func _spawn_shell(root: Node, world_pos: Vector2, large: bool = false) -> void:
	var shell := Sprite2D.new()
	shell.texture = SHELL_TEX_LARGE if large else SHELL_TEX
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
