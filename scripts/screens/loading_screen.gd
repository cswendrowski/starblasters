class_name LoadingScreen
extends Control

# Inter-node loading screen (Roman 2026-06-19). Shown while the next combat level
# loads: the chosen ship "flies at speed" up the screen toward a destination, over a
# black void of swift star-parallax + warp streaks. When loading finishes, fly_off()
# launches the ship off the top — the same accelerate-and-vanish beat as the real
# level-exit (`main.gd::_run_outro`) — then emits `flight_complete` for the caller to
# swap scenes.
#
# RENDER MODEL (mirrors the HD dev-tool pattern, scripts/dev/player_fx_lab.gd):
#   HD (1920×1080) Control root → a native 480×270 SubViewport holds the WORLD
#   (black + the two star CanvasLayers + warp streaks + the ship), upscaled 4× by the
#   SubViewportContainer. The "Flying to …" title is HD Control text composited on top
#   (crisp). The ship, its engine plume, and the fly-off tween all live in native 480
#   space, so the exit reads identically to combat.
#
# Identity (ship variant + livery + hull DAMAGE + destination) defaults from the Run autoload — the
# ship shown is the player's ACTUAL ship in its ACTUAL damage state, so a battered ship arrives at
# the next fight looking battered. A caller (or the dev lab) can override the public fields before
# add_child, or live via the set_*/rebuild_*/apply_hull methods. Set `manage_hd_scope = false` when
# embedding under a host that already owns an HD scope (the dev lab) to avoid a double scale swap.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
# Both preloaded (not via FlyoverBackdrop's class_name): a fresh class_name isn't registered when
# this scene is parsed under the -s headless test harness until the cache regenerates.
const FlyoverPlanner = preload("res://scripts/parallax/flyover_planner.gd")
const FlyoverBackdropScript = preload("res://scripts/parallax/flyover_backdrop.gd")

const STARS_SCENE := "res://scenes/parallax/layers/layer_stars.tscn"

# Player scenes per variant (index = Run.ship_variant) come from the canonical ShipCatalog. We
# render the REAL combat player (idle: no input / collision / weapons, never dies) rather than a
# sprite mock, so the livery shader, engine glow AND the live damage tells (engine_torch /
# damage_smoke_trail / spark_trail) match combat.

const NATIVE_W := 480.0
const SHIP_X := NATIVE_W / 2.0   # 240 — native viewport centre (matches _run_outro)
const FLYOFF_TARGET_Y := -120.0  # off the top edge, same as _run_outro
const WORLD_SCALE := 4.0         # 1920/480 — maps native 480 world coords into the HD canvas

# Run fields the real player's _ready()/start() can WRITE on spawn (super-charge refill in start();
# SidePods part writes run.ammo). The loading screen is a READ-ONLY visual, so we snapshot these
# around the throwaway player's init and restore them — it must never damage/repair/re-arm the run.
const _RUN_GUARD_FIELDS := ["super_charges", "max_super_charges", "ammo", "secondary_ammo", "secondary_ammo_max", "active_cannon_idx"]

# Engine audio (Roman 2026-06-19). One of two burn loops fades in FROM THE SHIP for the life of the
# loading screen; a random exit-thruster one-shot fires on fly-off as the burn fades out.
const BURN_LOOP_CLIPS := [
	"res://assets/audio/engines/engine_burn_loop_1.ogg",
	"res://assets/audio/engines/engine_burn_loop_2.ogg",
]
const EXIT_THRUSTER_CLIPS := [
	"res://assets/audio/engines/exit_thruster_1.ogg",
	"res://assets/audio/engines/exit_thruster_2.ogg",
]
const BURN_VOLUME_DB := -1.0    # steady loop level once faded in
const BURN_QUIET_DB := -40.0    # near-silent fade endpoint
const BURN_FADE_IN := 0.8
const BURN_FADE_OUT := 0.5
const EXIT_THRUSTER_VOLUME_DB := 3.0   # fly-off one-shot gain

signal flight_complete

# ---- Identity (set before add_child, or via configure(); -1/false = read from Run) ----
@export var poi_name: String = ""
@export var ship_variant: int = -1
@export var ship_hull: int = -1       # current hull; -1 = read Run.current_hull (carried damage)
@export var ship_max_hull: int = -1   # max hull;     -1 = read Run.max_hull
@export var manage_hd_scope: bool = true

# ---- Flyover backdrop (Planet Flyover consumer, Phase B2) ----
# When non-empty, `stellar_override` REPLACES Run.current_stellar for flyover planning (the
# Loading Screen Lab injects a planet dict here). `night_override`: -1 auto (plan decides) /
# 0 force day / 1 force night — a lab knob merged over the plan's night bool.
@export var stellar_override: Dictionary = {}
@export var night_override: int = -1

# ---- Visual tuning knobs (the dev lab drives these; defaults are the shipped look) ----
@export var star_drift: float = 18000.0       # star scroll rate — "swiftness" of the rush
@export var star_alpha: float = 0.5           # fade the star layers (1 = full bright)
@export var streak_count: int = 4
@export var streak_speed: float = 1600.0
@export var streak_width_min: float = 1.0     # px — streaks render 1..2px wide (texture is 1px wide)
@export var streak_width_max: float = 1.5
@export var streak_length: float = 80.0       # px — base streak length (texture height)
@export var ship_rest_y: float = 150.0        # native-Y the ship hovers around
@export var ship_drift_ax: float = 5.0        # gentle centre-drift amplitude (px)
@export var ship_drift_ay: float = 1.5
@export var ship_drift_period_x: float = 2.4  # seconds per drift cycle
@export var ship_drift_period_y: float = 1.9
@export var flyoff_time: float = 1.0

var _hd: HdViewportScope = null
var _world: Node2D = null
var _stars: CanvasLayer = null
var _streaks: GPUParticles2D = null
var _ship: Node2D = null
var _flyover_plan: Dictionary = {}   # {} = space starfield; non-empty = Planet Flyover backdrop
var _flyover_layer: CanvasLayer = null
var _flyover: FlyoverBackdropScript = null
var _burn_player: AudioStreamPlayer2D = null   # looping engine burn, child of the ship
var _burn_tween: Tween = null
var _name_label: Label = null
var _enroute_label: Label = null
var _t: float = 0.0
var _flying: bool = true
var _built: bool = false


func _ready() -> void:
	if manage_hd_scope:
		_hd = HdScreen.enter(self)
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolve_identity()
	_compute_flyover_plan()
	_build_world()
	# Flyover levels swap the space starfield for the Planet Flyover backdrop (skip stars/streaks).
	if _flyover_plan.is_empty():
		rebuild_streaks()
		_build_stars()
	else:
		_build_flyover()
	rebuild_ship()
	_build_title()
	_built = true


# Render the world DIRECTLY in the HD canvas at ×4 scale — NOT via a SubViewport. A SubViewport
# upscale (480→1920) bakes the scene into one raster, and the window then resamples THAT to the
# physical display (blurry on fullscreen / >1080p monitors — the sharp ship sprite shows it; soft
# backdrops hide it, which is why add_upscaled_backdrop "works" for them). Drawing the pixel-art
# sprites directly, nearest-filtered and scaled ×4, lets the GPU sample the original 16px textures
# at the FINAL physical resolution — crisp at any window size, exactly like combat. All world
# content keeps its native 480 coordinates; the ×4 maps them into the 1920 HD space.
func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	add_child(_world)


# Override identity in one call (caller-facing). Pass -1 for any of variant/hull/max_hull to defer
# that field to the Run value. Livery is always taken from Run (the real player reads it).
func configure(p_poi: String, p_variant: int = -1, p_hull: int = -1, p_max_hull: int = -1) -> void:
	poi_name = p_poi
	ship_variant = p_variant
	ship_hull = p_hull
	ship_max_hull = p_max_hull
	if _built:
		_resolve_identity()
		rebuild_ship()
		set_poi_name(poi_name)


func _resolve_identity() -> void:
	var run := get_node_or_null("/root/Run")
	if ship_variant < 0:
		ship_variant = int(run.ship_variant) if run != null and "ship_variant" in run else 0
	ship_variant = clampi(ship_variant, 0, ShipCatalog.count() - 1)
	# NOTE: damage state is NOT read here. apply_hull() derives it from the spawned player's own
	# loadout max_hull + Run.current_hull (identical to combat) — reading Run.max_hull here would use
	# the stale snapshot and show damage on an already-repaired ship. ship_hull/ship_max_hull stay -1
	# in production (apply_hull's combat-matching path); the dev lab sets them to force a test state.
	if poi_name.is_empty():
		poi_name = _default_poi_name(run)


# Deterministic-per-node destination name (same node → same name across map re-entries),
# falling back to a fresh random name outside a run. Mirrors run_state's per-POI seeding.
func _default_poi_name(run: Node) -> String:
	var seed_value: int = 0
	if run != null and "run_seed" in run:
		seed_value = int(run.run_seed) ^ abs(hash(String(run.current_node_id)))
	else:
		seed_value = randi()
	return SectorNameGenerator.generate(seed_value)


# ---- Flyover backdrop -----------------------------------------------------

# Decide, ONCE, whether this fly-to lands on a Planet Flyover level. stellar_override (lab) beats
# Run.current_stellar; absent Run / empty stellar / planner returning {} → the normal space screen.
# The lab night_override is merged over the planned night bool.
func _compute_flyover_plan() -> void:
	var run := get_node_or_null("/root/Run")
	var stellar: Dictionary = {}
	if not stellar_override.is_empty():
		stellar = stellar_override
	elif run != null and "current_stellar" in run and run.current_stellar is Dictionary:
		stellar = run.current_stellar
	if stellar.is_empty():
		_flyover_plan = {}
		return
	var node_id: String = ""
	var run_seed: int = 0
	if run != null:
		if "current_node_id" in run:
			node_id = String(run.current_node_id)
		if "run_seed" in run:
			run_seed = int(run.run_seed)
	_flyover_plan = FlyoverPlanner.plan(stellar, run_seed, node_id)
	if not _flyover_plan.is_empty() and night_override >= 0:
		_flyover_plan["night"] = (night_override == 1)


# Build the flyover stack in its OWN CanvasLayer (layer -10, scale ×4 — same pattern as the stars
# layer: CanvasLayers ignore Node2D transforms, so scale directly). The FlyoverBackdrop's night
# CanvasModulate lives inside this layer, darkening ONLY the backdrop (ship + title stay lit). The
# ship is registered as the single shadow caster after rebuild_ship() spawns it; the world is HD ×4
# so casters convert with caster_coord_scale = 0.25. NOT parented under World (which would expose a
# hull/max_hull-free child there is fine, but the backdrop belongs on its own canvas anyway).
func _build_flyover() -> void:
	_teardown_flyover()
	var layer := CanvasLayer.new()
	layer.name = "FlyoverLayer"
	layer.layer = -10
	layer.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	add_child(layer)
	var bd := FlyoverBackdropScript.new()
	bd.name = "FlyoverBackdrop"
	bd.base_z = 0
	bd.caster_coord_scale = 0.25   # ship global_position is HD ×4; masks are native 480×270
	layer.add_child(bd)
	bd.apply_settings(_flyover_plan)
	_flyover_layer = layer
	_flyover = bd


# Recompute the plan and swap the backdrop live between the space starfield and the flyover stack.
# Dev-lab entry point (Destination / Night knobs); keeps THIS LoadingScreen instance (and the lab's
# slider closures that capture it) stable rather than re-instancing.
func rebuild_backdrop() -> void:
	_compute_flyover_plan()
	if _flyover_plan.is_empty():
		_teardown_flyover()
		if _stars == null or not is_instance_valid(_stars):
			_build_stars()
		if _streaks == null or not is_instance_valid(_streaks):
			rebuild_streaks()
	else:
		_teardown_space()
		_build_flyover()
		_register_ship_caster()


func _teardown_flyover() -> void:
	if _flyover != null and is_instance_valid(_flyover) and _ship != null and is_instance_valid(_ship):
		_flyover.unregister_caster(_ship)
	if _flyover_layer != null and is_instance_valid(_flyover_layer):
		_flyover_layer.queue_free()
	_flyover_layer = null
	_flyover = null


func _teardown_space() -> void:
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = null
	if _streaks != null and is_instance_valid(_streaks):
		_streaks.queue_free()
	_streaks = null


# Register the spawned ship as the single flyover shadow caster: a one-frame AtlasTexture of the
# ship's 3-hframe body strip (frame 1 = level flight). Idempotent — unregisters any prior player
# node first so lab respawns don't leave a stale caster in the mask viewports.
func _register_ship_caster() -> void:
	if _flyover == null or not is_instance_valid(_flyover):
		return
	if _ship == null or not is_instance_valid(_ship):
		return
	_flyover.unregister_caster(_ship)
	var body := _find_ship_body(_ship)
	if body == null or body.texture == null:
		return
	var tex := _single_frame_tex(body.texture, body.hframes, 1)
	if tex != null:
		_flyover.register_caster(_ship, tex)


# The player's body sprite: the conventional "Ship" layer (player.tscn), else first textured Sprite2D.
func _find_ship_body(p: Node) -> Sprite2D:
	var s := p.get_node_or_null("Ship")
	if s is Sprite2D:
		return s as Sprite2D
	for c in p.find_children("*", "Sprite2D", true, false):
		if c is Sprite2D and (c as Sprite2D).texture != null:
			return c as Sprite2D
	return null


# One frame of an N-hframe sprite strip as a standalone texture (mirrors planet_flyover_lab).
func _single_frame_tex(tex: Texture2D, hframes: int, frame: int) -> AtlasTexture:
	if tex == null:
		return null
	var frames: int = maxi(1, hframes)
	var fw: float = float(tex.get_width()) / float(frames)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(fw * float(clampi(frame, 0, frames - 1)), 0.0, fw, float(tex.get_height()))
	return at


# ---- World build ----------------------------------------------------------

func _build_stars() -> void:
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = load(STARS_SCENE).instantiate()
	# layer_stars is a CanvasLayer (viewport-relative, ignores the World Node2D's transform), so scale
	# it directly. Stars/DeepSpace are authored in 480 space; ×4 fills the HD canvas. Its layer=-10
	# keeps it behind the World + title regardless of tree order.
	_stars.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	add_child(_stars)
	if _stars.has_method("reseed"):
		_stars.reseed(randi())
	apply_star_alpha()


# Fade the star fields (not the black backdrop) to taste. The DeepSpace ColorRect is a
# sibling of the two Parallax2D star containers, so modulating those leaves the void black.
func apply_star_alpha() -> void:
	if _stars == null or not is_instance_valid(_stars):
		return
	for nm in ["FarStars", "NearStars"]:
		var n = _stars.get_node_or_null(nm)
		if n != null:
			n.modulate.a = clampf(star_alpha, 0.0, 1.0)


# Dedicated warp streaks. A 1px-WIDE, tall texture means uniform particle scale sets the
# on-screen WIDTH (1..2px) while the texture HEIGHT carries the length — long but thin, which
# the shared combat streak layer (a 2px texture scaled uniformly) cannot do. Behind the ship.
func rebuild_streaks() -> void:
	if _streaks != null and is_instance_valid(_streaks):
		_streaks.queue_free()
		_streaks = null
	var p := GPUParticles2D.new()
	p.name = "WarpStreaks"
	p.amount = maxi(1, streak_count)
	p.lifetime = (320.0 + streak_length) / maxf(streak_speed, 1.0)
	p.preprocess = p.lifetime   # populate the field on spawn rather than empty
	p.local_coords = false
	p.position = Vector2(SHIP_X, -10.0)
	p.z_index = -2              # behind the ship (z 0) and its exhaust trail (z -1)
	p.z_as_relative = false
	p.texture = _build_streak_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(240.0, 6.0, 0.0)
	m.direction = Vector3(0, 1, 0)   # downward = ship flying up
	m.spread = 0.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = streak_speed * 0.8
	m.initial_velocity_max = streak_speed * 1.2
	m.scale_min = streak_width_min   # 1px-wide texture → scale == on-screen width (px)
	m.scale_max = streak_width_max
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(0.55, 0.7, 1.0, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive glow
	p.material = cmat
	_streaks = p
	_world.add_child(p)


# 1px-wide vertical gradient (faint tips, bright middle); height = streak length.
func _build_streak_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 1
	t.height = int(maxf(streak_length, 2.0))
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t


# Spawn the real combat player as an idle presentation copy: no input, no collision, no weapons,
# never dies. Its _ready wires the livery shader, engine glow + the live damage tells; setting hull
# from Run then lights up the tells the ship would show in combat at the same damage.
func rebuild_ship() -> void:
	if _ship != null and is_instance_valid(_ship):
		# Drop the outgoing ship's flyover caster before it frees (avoid a stale mask entry).
		if _flyover != null and is_instance_valid(_flyover):
			_flyover.unregister_caster(_ship)
		_ship.queue_free()
	var idx: int = clampi(ship_variant, 0, ShipCatalog.count() - 1)
	var p: Node2D = load(ShipCatalog.scene_path(idx)).instantiate()
	if "controls_enabled" in p:
		p.controls_enabled = false   # skips input/fire; pins the level-flight frame
	if "invincible" in p:
		p.invincible = true
	if "is_alive" in p:
		p.is_alive = true
	# READ-ONLY guard: adding the player runs its full combat _ready() (applies the loadout + start()),
	# which can write run.super_charges / run.ammo etc. Snapshot those, spawn, then restore — this
	# presentation copy must leave the run's state exactly as it found it.
	var run := get_node_or_null("/root/Run")
	var snap: Dictionary = {}
	if run != null:
		for f in _RUN_GUARD_FIELDS:
			if f in run:
				snap[f] = run.get(f)
	_world.add_child(p)
	if run != null:
		for f in snap:
			run.set(f, snap[f])
	if "monitoring" in p:
		p.monitoring = false
	if "monitorable" in p:
		p.monitorable = false
	p.position = Vector2(SHIP_X, ship_rest_y)
	_ship = p
	# Drop the shield FX (the Ship/Shield bubble + the code-built ShieldRing) — a calm loading
	# screen shouldn't carry the combat shield graphic. Hides any shield CanvasItem on the ship.
	for n in p.find_children("*Shield*", "", true, false):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	# The player's _ready attaches its engine trail + damage tells (some add deferred). Let them
	# settle a frame, then drive the hull so the tells reflect the carried damage.
	await get_tree().process_frame
	if is_instance_valid(_ship):
		apply_hull()
		_register_ship_caster()   # no-op unless a flyover backdrop is active
	_start_burn_loop()


# ---- Engine audio ---------------------------------------------------------

# Fade one of the two burn loops in FROM THE SHIP (child of the ship → emanates from it + follows
# the drift), looping for the life of the loading screen. Re-armable (dev-lab respawn/replay).
func _start_burn_loop() -> void:
	if _burn_tween != null and _burn_tween.is_valid():
		_burn_tween.kill()
	if _burn_player != null and is_instance_valid(_burn_player):
		_burn_player.queue_free()
		_burn_player = null
	if _ship == null or not is_instance_valid(_ship):
		return
	var stream := load(BURN_LOOP_CLIPS[randi() % BURN_LOOP_CLIPS.size()]) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var pl := AudioStreamPlayer2D.new()
	pl.name = "BurnLoop"
	pl.stream = stream
	pl.bus = "SFX"
	pl.volume_db = BURN_QUIET_DB
	_ship.add_child(pl)
	pl.play()
	_burn_player = pl
	_burn_tween = create_tween()
	_burn_tween.tween_property(pl, "volume_db", BURN_VOLUME_DB, BURN_FADE_IN)


# Fade the burn loop out, then free it (on fly-off / re-test).
func _fade_out_burn() -> void:
	if _burn_tween != null and _burn_tween.is_valid():
		_burn_tween.kill()
		_burn_tween = null
	if _burn_player == null or not is_instance_valid(_burn_player):
		return
	var pl := _burn_player
	_burn_player = null
	_burn_tween = create_tween()
	_burn_tween.tween_property(pl, "volume_db", BURN_QUIET_DB, BURN_FADE_OUT)
	_burn_tween.tween_callback(pl.queue_free)


# One-shot exit-thruster on fly-off. Non-positional so it stays full-volume as the ship leaves.
func _play_exit_thruster() -> void:
	var stream := load(EXIT_THRUSTER_CLIPS[randi() % EXIT_THRUSTER_CLIPS.size()]) as AudioStream
	if stream == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	pl.bus = "SFX"
	pl.volume_db = EXIT_THRUSTER_VOLUME_DB
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)


# Drive the ship's hull → emits hull_changed → engine_torch / damage_smoke_trail / spark_trail update
# to the carried damage severity (1 - hull/max). Matches combat EXACTLY, so a repaired ship reads as
# repaired: the player's own start() already set max_hull from the LIVE loadout (apply_run_upgrades =
# 2 + module_hull_bonus), so we keep THAT — never the stale Run.max_hull snapshot (the old bug: it
# diverged from the loadout max, making repaired ships still show damage) — and load only the current
# hull the way main.gd does. Read-only: reads Run.current_hull, never writes it.
func apply_hull() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	# Dev-lab override: an explicit max/current pair set via the Hull sliders.
	if ship_max_hull > 0:
		var mh: int = maxi(1, ship_max_hull)
		var h: int = clampi(ship_hull if ship_hull >= 0 else mh, 0, mh)
		if "max_hull" in _ship:
			_ship.max_hull = mh
		if "hull" in _ship:
			_ship.hull = h
		if _ship.has_signal("hull_changed"):
			_ship.hull_changed.emit(mh, h)
		return
	# Production: keep the player's loadout-derived max_hull; load current hull from Run like combat
	# (main.gd: player.hull = mini(run.current_hull, player.max_hull); left at max when unsaved).
	var max_h: int = int(_ship.max_hull) if "max_hull" in _ship else 1
	var run := get_node_or_null("/root/Run")
	if run != null and "current_hull" in run and int(run.current_hull) > 0 and "hull" in _ship:
		_ship.hull = mini(int(run.current_hull), max_h)
	if _ship.has_signal("hull_changed"):
		_ship.hull_changed.emit(max_h, int(_ship.hull) if "hull" in _ship else max_h)


func _build_title() -> void:
	# HD title block, top-centre. Composited over the upscaled world (crisp at 1:1).
	var box := VBoxContainer.new()
	box.name = "TitleBox"
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 88.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var eyebrow := _label("FLYING TO", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_FAINT)
	box.add_child(eyebrow)

	_name_label = _label(poi_name.to_upper(), UiTheme.FONT_SIZE_TITLE + 12, UiTheme.COLOR_ACCENT)
	box.add_child(_name_label)

	_enroute_label = _label("• EN ROUTE •", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	box.add_child(_enroute_label)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---- Live setters (dev lab) -----------------------------------------------

func set_poi_name(p: String) -> void:
	poi_name = p
	if _name_label != null and is_instance_valid(_name_label):
		_name_label.text = p.to_upper()


# ---- Runtime --------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _stars != null and is_instance_valid(_stars) and _stars.has_method("scroll_stars"):
		_stars.scroll_stars(star_drift * delta)
	if _enroute_label != null and is_instance_valid(_enroute_label):
		_enroute_label.modulate.a = 0.45 + 0.35 * (0.5 + 0.5 * sin(_t * TAU * 0.6))
	if _flying and _ship != null and is_instance_valid(_ship):
		var dx: float = sin(_t * TAU / maxf(ship_drift_period_x, 0.1)) * ship_drift_ax
		var dy: float = sin(_t * TAU / maxf(ship_drift_period_y, 0.1) + 1.3) * ship_drift_ay
		_ship.position = Vector2(SHIP_X + dx, ship_rest_y + dy)


# Loading finished → launch the ship off the top, then signal. Idempotent.
func fly_off() -> void:
	if not _flying:
		return
	_flying = false
	_play_exit_thruster()
	_fade_out_burn()
	if _ship == null or not is_instance_valid(_ship):
		emit_signal("flight_complete")
		return
	var tw := create_tween()
	tw.tween_property(_ship, "position", Vector2(SHIP_X, FLYOFF_TARGET_Y), flyoff_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void: emit_signal("flight_complete"))


# Release the HD content-scale scope. The launcher calls this under the black cover of the
# exit swap (combat is native 480 — leaving HD up would render it blown-up). No-op when this
# screen never owned a scope (embedded in the dev lab with manage_hd_scope=false).
func drop_hd_scope() -> void:
	HdScreen.drop(_hd)
	_hd = null


# Reset to the hovering "flying" state (dev lab re-test).
func replay() -> void:
	_flying = true
	_t = 0.0
	if _ship != null and is_instance_valid(_ship):
		_ship.position = Vector2(SHIP_X, ship_rest_y)
	_start_burn_loop()
