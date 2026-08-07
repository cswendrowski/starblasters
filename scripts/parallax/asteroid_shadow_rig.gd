extends Node

# Asteroid drop shadows — ports the Planet Flyover lab's cloud-shadow rig (see
# scripts/dev/planet_flyover_lab.gd) to the decorative parallax asteroids. Every
# caster's silhouette is drawn into a per-band shadow-mask SubViewport (offset +
# scale baked into the mask sprites); Asteroids.gdshader samples the mask at
# SCREEN_UV and darkens rgb inside the rock's base silhouette. Deeper bands:
# bigger offset, SMALLER shadow (the depth read), slightly weaker — the exact
# size settings the flyover cloud layers use (Far/Mid/Near → far/mid/near).
#
# Casters: by default the rig auto-tracks the production "player" + "enemies"
# groups every frame (zero wiring in combat code — dying enemies free their mask
# sprites when the caster goes invalid). Labs can drop demo Sprite2Ds into those
# groups, or call register_caster() directly with auto_track off.
#
# Ownership: backdrop_coordinator creates one rig (asteroid_shadows export) only
# when decorative rocks will actually spawn; layer_stellar finds it via the
# "asteroid_shadow_rig" group at rock spawn and binds mask_texture(band) +
# band_strength(band) into the rock's duplicated material.

const GROUP := "asteroid_shadow_rig"
const BANDS := ["far", "mid", "near"]
# Per-band offset/scale/weight keyed far/mid/near — the flyover cloud-shadow settings, verbatim.
# The DIRECTION is no longer one of them: it comes from SceneLight (225°, canonical for the whole
# scene — docs/scene_light_direction_2026-07-28.md). The old local `SHADOW_DIR = (0.35, 0.9)` was a
# ~249° sun inherited from the flyover lab's CLOUD shadows, where a near-vertical offset stood for
# cloud height over a scrolling surface; on side-lit rocks it just read as a second sun.
const SHADOW_DIST := {"far": 26.0, "mid": 16.0, "near": 8.0}
const SHADOW_SCALE := {"far": 0.25, "mid": 0.5, "near": 1.0}
const SHADOW_MULT := {"far": 0.8, "mid": 0.9, "near": 1.0}

# Master shadow opacity (the flyover's "Cloud shadow" knob, same 0.35 default);
# each band multiplies in its SHADOW_MULT via band_strength().
@export var strength: float = 0.35
# Scan the player/enemies groups each frame. Off = manual register_caster() only.
@export var auto_track: bool = true

var _mask_vps := {}   # band -> SubViewport
var _tracked := {}    # caster instance_id -> {caster, src (Sprite2D), masks: {band: Sprite2D}}


func _ready() -> void:
	add_to_group(GROUP)
	for band in BANDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 270)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.gui_disable_input = true
		vp.handle_input_locally = false
		add_child(vp)
		_mask_vps[band] = vp


func mask_texture(band: String) -> Texture2D:
	var vp: SubViewport = _mask_vps.get(band)
	return vp.get_texture() if vp != null else null


func band_strength(band: String) -> float:
	return strength * float(SHADOW_MULT.get(band, 1.0))


# Track a caster: one silhouette sprite per band, living in that band's mask
# viewport. The silhouette mirrors the caster's BODY sprite (texture + frame +
# global transform) each frame — children (shields, glow layers) don't cast.
func register_caster(caster: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var id := caster.get_instance_id()
	if _tracked.has(id):
		return
	var src := _find_source_sprite(caster)
	if src == null:
		return
	var masks := {}
	for band in BANDS:
		var ms := Sprite2D.new()
		ms.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ms.modulate = Color.BLACK   # the shader only reads mask alpha; black keeps debug views sane
		_mask_vps[band].add_child(ms)
		masks[band] = ms
	_tracked[id] = {"caster": caster, "src": src, "masks": masks}


func _process(_delta: float) -> void:
	if auto_track:
		for caster in get_tree().get_nodes_in_group("player"):
			register_caster(caster)
		for caster in get_tree().get_nodes_in_group("enemies"):
			register_caster(caster)
	_update_masks()


func _update_masks() -> void:
	var dir := SceneLight.shadow_dir()
	for id in _tracked.keys():
		var rec: Dictionary = _tracked[id]
		# Untyped on purpose: a caster/src may have been freed since last frame (enemies die + free
		# constantly in combat). Assigning a freed instance to a TYPED var throws "previously freed
		# instance"; holding it untyped lets the is_instance_valid guard below clean it up quietly.
		var caster = rec["caster"]
		var src = rec["src"]
		if not is_instance_valid(caster) or not is_instance_valid(src):
			for band in rec["masks"]:
				var dead: Sprite2D = rec["masks"][band]
				if is_instance_valid(dead):
					dead.queue_free()
			_tracked.erase(id)
			continue
		var vis: bool = src.is_visible_in_tree()
		for band in BANDS:
			var ms: Sprite2D = rec["masks"][band]
			ms.visible = vis
			if not vis:
				continue
			ms.texture = src.texture
			ms.hframes = src.hframes
			ms.vframes = src.vframes
			ms.frame = src.frame
			ms.flip_h = src.flip_h
			ms.flip_v = src.flip_v
			ms.centered = src.centered
			ms.offset = src.offset
			# Offset + scale baked into the mask sprite, exactly like the flyover.
			ms.position = src.global_position + dir * float(SHADOW_DIST[band])
			ms.rotation = src.global_rotation
			ms.scale = src.global_scale * float(SHADOW_SCALE[band])


# The caster's body sprite: the node itself (lab demo sprites), else the
# conventional layer names — enemies carry "Sprite2D", the player carries
# "Ship" (see enemy-marker-layer naming). Fallback: first Sprite2D child.
func _find_source_sprite(caster: Node) -> Sprite2D:
	if caster is Sprite2D:
		return caster as Sprite2D
	var s: Node = caster.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s as Sprite2D
	s = caster.get_node_or_null("Ship")
	if s is Sprite2D:
		return s as Sprite2D
	for child in caster.get_children():
		if child is Sprite2D:
			return child as Sprite2D
	return null
