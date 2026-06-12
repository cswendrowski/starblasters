extends Node

# Static helper to play an explosion at a position. Spawns the explosion
# scene as a child of `get_tree().root` so it survives whatever node was
# blown up. Usage:
#   ExplosionFx.play(global_position, 1.0)
#   ExplosionFx.play(boss.global_position, 3.0, false)  # no extra light

const EXPLOSION_SCENE = preload("res://scenes/effects/explosion.tscn")
const ExplosionSfx = preload("res://scripts/effects/explosion_sfx.gd")

# Named death-explosion variants. The enemy dev tool / enemy_base.explosion_variant
# select by name; scene_for() resolves it (unknown name -> default). Add new
# variant scenes here.
const VARIANTS := {
	"default": EXPLOSION_SCENE,
	"small_circle": preload("res://scenes/effects/explosion_small_circle.tscn"),
	"ball": preload("res://scenes/effects/explosion_small_circle.tscn"),  # zealot enemies
	"small_then_default": preload("res://scenes/effects/explosion_combo.tscn"),  # spark → big boom
}

static func variant_names() -> Array:
	return VARIANTS.keys()

static func scene_for(variant: String) -> PackedScene:
	return VARIANTS.get(variant, EXPLOSION_SCENE)


# ── Centralized, tunable explosion system (Roman 2026-06-12) ───────────────────────────────────
# One config drives every aspect of an explosion EVENT: how big each boom is (size), how wide they
# spread (area), how long they burn (duration), how many there are (density) and how fast they
# stagger, the type (basic / ball), plus the UNIVERSAL core aspects glow + shockwave. Legacy
# play()/burst()/scene_for() stay for the existing callers; new tunable callers use play_config().

const BALL_STRIP = preload("res://graphics/effects/explosion_small_circle.png")

# Per-type base look — the "basic" vs "ball" defaults play_config starts from before applying cfg.
const TYPE_DEFAULTS := {
	"basic": {"frames": 8, "frame_duration": 0.07, "satellite_radius": 28.0, "sparks": 18, "debris": 8, "strip": null},
	"ball":  {"frames": 9, "frame_duration": 0.05, "satellite_radius": 12.0, "sparks": 10, "debris": 3, "strip": BALL_STRIP},
}

const EXPLOSION_DEFAULTS := {
	"type": "basic",      # "basic" | "ball" | "mixed" (random basic/ball per boom)
	"size": 1.0,          # scale of each boom
	"area": 10.0,         # px scatter radius — how wide the booms spread
	"duration": -1.0,     # per-frame seconds; < 0 = the type's natural duration
	"density": 1.0,       # number of main booms in the event (1 = single, higher = a cluster)
	"stagger": 0.06,      # seconds between booms
	"secondaries": 1.0,   # per-boom satellite multiplier (the small scattered sub-booms)
	"glow": 0.9,          # additive halo + light intensity multiplier (Expl. Tuner bake 2026-06-12)
	"shockwave": 0.1,     # expanding pressure ring on the lead boom (Expl. Tuner bake; 0 = off)
	"sparks": 1.0,        # spark count multiplier
	"debris": 1.0,        # debris count multiplier
	"light": true,
	"sound": true,
}


# Play a fully-configured explosion event. Returns the lead boom (the others may be staggered).
static func play_config(world_pos: Vector2, cfg: Dictionary = {}, parent: Node = null) -> Node2D:
	var c: Dictionary = EXPLOSION_DEFAULTS.duplicate(true)
	c.merge(cfg, true)
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node = parent if (parent != null and is_instance_valid(parent)) else (tree.root if tree != null else null)
	if p == null:
		return null
	var count: int = maxi(1, int(round(float(c["density"]))))
	# One SFX for the whole event, louder with more booms (bigger enemy = bigger boom).
	if bool(c["sound"]):
		ExplosionSfx.play(world_pos, float(c["size"]) * clampf(1.0 + float(count - 1) * 0.25, 1.0, 2.5), p)
	var lead: Node2D = _spawn_config(world_pos, c, p, true)
	for i in range(1, count):
		var delay: float = float(i) * float(c["stagger"])
		if delay <= 0.001 or tree == null:
			_spawn_config(world_pos, c, p, false)
		else:
			tree.create_timer(delay).timeout.connect(_spawn_config.bind(world_pos, c, p, false))
	return lead


const MIXED_DELAY := 0.04   # "a couple frames" — gap between the ball and the basic boom underneath

static func _spawn_config(world_pos: Vector2, c: Dictionary, parent: Node, is_lead: bool) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var area: float = float(c["area"])
	var off: Vector2 = Vector2.ZERO if is_lead else Vector2(randf_range(-area, area), randf_range(-area, area))
	var pos: Vector2 = world_pos + off
	if String(c["type"]) == "mixed":
		# Open with the BALL on top; a couple frames later the BASIC boom lands UNDERNEATH it.
		var ball: Node2D = _spawn_typed(pos, c, parent, "ball", is_lead, 0)
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.create_timer(MIXED_DELAY).timeout.connect(_spawn_typed.bind(pos, c, parent, "basic", false, -3))
		else:
			_spawn_typed(pos, c, parent, "basic", false, -3)
		return ball
	return _spawn_typed(pos, c, parent, String(c["type"]), is_lead, 0)


static func _spawn_typed(pos: Vector2, c: Dictionary, parent: Node, typ: String, is_lead: bool, z: int) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var td: Dictionary = TYPE_DEFAULTS.get(typ, TYPE_DEFAULTS["basic"])
	var inst: Node2D = EXPLOSION_SCENE.instantiate()
	inst.global_position = pos
	inst.z_index = z
	if td["strip"] != null:
		inst.strip = td["strip"]
	inst.frames = int(td["frames"])
	inst.base_scale = float(c["size"])
	inst.frame_duration = (float(c["duration"]) if float(c["duration"]) >= 0.0 else float(td["frame_duration"]))
	inst.max_radius = float(td["satellite_radius"])
	inst.density = float(c["secondaries"])
	inst.glow_mult = float(c["glow"])
	inst.shockwave = (float(c["shockwave"]) if is_lead else 0.0)   # one pressure ring per event
	inst.spark_count = int(round(float(td["sparks"]) * float(c["sparks"])))
	inst.debris_count = int(round(float(td["debris"]) * float(c["debris"])))
	inst.emit_light = bool(c["light"])
	parent.add_child(inst)
	return inst

# `parent` lets a caller spawn the blast into a specific container (e.g. the
# hangar's SubViewport world) instead of the window root — needed so effects
# land in the same coordinate space as the thing that blew up. Defaults to the
# window root (combat), preserving prior behavior.
static func play(world_pos: Vector2, scale: float = 1.0, with_light: bool = true, parent: Node = null, scene: PackedScene = null, with_sound: bool = true) -> Node2D:
	var src: PackedScene = scene if scene != null else EXPLOSION_SCENE
	var inst: Node2D = src.instantiate()
	inst.global_position = world_pos
	if "base_scale" in inst:
		inst.base_scale = scale
	if "emit_light" in inst:
		inst.emit_light = with_light
	# Fall back to the window root if no parent given OR it was freed (a staggered
	# burst can outlive a transient container like the hangar world).
	var p: Node = parent if (parent != null and is_instance_valid(parent)) else Engine.get_main_loop().root
	p.add_child(inst)
	# Distance-based explosion SFX (close/medium/distant). Silenced on burst sub-blasts so a
	# multi-blast death sounds once, not N times.
	if with_sound:
		ExplosionSfx.play(world_pos, scale, p)
	return inst


# Spawn `count` explosions at `world_pos` with small spatial jitter and
# staggered timing so larger enemies read as "many simultaneous blasts"
# rather than one oversized one (Roman 2026-05-18). All blasts are at
# native 1× scale.
static func burst(world_pos: Vector2, count: int = 1, jitter_radius: float = 10.0, stagger: float = 0.06, parent: Node = null, scene: PackedScene = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# One explosion SFX for the whole death, scaled up by blast count (bigger enemy = bigger boom).
	var snd_parent: Node = parent if (parent != null and is_instance_valid(parent)) else tree.root
	ExplosionSfx.play(world_pos, clampf(1.0 + float(count - 1) * 0.25, 1.0, 2.5), snd_parent)
	for i in count:
		var delay: float = float(i) * stagger
		if delay <= 0.001:
			_spawn_one(world_pos, jitter_radius, parent, scene)
		else:
			tree.create_timer(delay).timeout.connect(_spawn_one.bind(world_pos, jitter_radius, parent, scene))


static func _spawn_one(world_pos: Vector2, jitter_radius: float, parent: Node = null, scene: PackedScene = null) -> void:
	var off := Vector2(randf_range(-jitter_radius, jitter_radius), randf_range(-jitter_radius, jitter_radius))
	# with_sound=false — burst() already played one SFX for the whole death.
	play(world_pos + off, 1.0, true, parent, scene, false)
