extends Node2D

# Light-derived multi-shadow projector (PROTOTYPE — Roman 2026-06-26). A cheaper, more "grounded"
# alternative to fixed drop shadows for the dock cinematics: every registered CASTER throws a black
# silhouette of itself AWAY from each registered LIGHT, so an object near several lights gets several
# shadows. Re-projected each frame, so shadows sweep as the ship/lifter move and as lights pulse.
#
# Works entirely in GLOBAL space, so casters + lights only need to share one SubViewport canvas (they
# do — the bay). Shadow sprites are parented to a caller-chosen node (so they sit in the caster's own
# coordinate space, behind it) and pooled per caster.
#
# The dock lab compares two source sets: a single central KEY light (one shadow each) vs the bay's 2×3
# FILL lights (multi-shadow). Bright DYNAMIC lights (engines, grav lifters, head/tail) can be added on
# top — their shadows fade with the light's energy.

# Knobs (the lab/rail drives these live).
@export var shadow_length: float = 4.0     # silhouette offset (px) away from the light
@export var max_alpha: float = 0.5         # alpha of one full-strength shadow (overlaps darken further)
@export var falloff: float = 110.0         # px; a shadow fades to 0 by this distance from its light
@export var softness: float = 0.0          # extra silhouette scale (0 = caster-size, 0.3 = 30% bigger)
@export var max_per_caster: int = 6        # cap on shadows per object (perf + visual-clutter control)
@export var enabled: bool = true

var _casters: Array = []   # [{src, parent, z, pool: Array[Sprite2D]}]
var _lights: Array = []    # [{node, weight, dynamic, ref}]


func clear_casters() -> void:
	for c in _casters:
		for s in c["pool"]:
			if is_instance_valid(s):
				s.queue_free()
	_casters.clear()


func clear_lights() -> void:
	_lights.clear()


# Register a sprite to cast. Its shadows are children of `parent` (so they live in the caster's space)
# at z `shadow_z`; the silhouette mirrors the sprite's frame/flip/rotation/scale each update. `parent`
# is a Node (may be a SubViewport canvas root, e.g. the bay viewport — not necessarily a Node2D).
func add_caster(src: Sprite2D, parent: Node, shadow_z: int = -2, lift_cb := Callable(), lift_px: float = 0.0) -> void:
	if src == null or parent == null:
		return
	# lift_cb (optional) returns 0..1 "altitude": 1 pulls the shadow `lift_px` FARTHER away + fainter
	# (reads as drop height), 0 = grounded (tight, dark). Used for the flying ship.
	_casters.append({"src": src, "parent": parent, "z": shadow_z, "pool": [], "lift_cb": lift_cb, "lift_px": lift_px})


# Register a light source. `weight` scales its shadows' darkness; if `dynamic`, the light's live energy
# (÷ `ref_energy`) further scales it, so engine/lifter/headlight shadows fade with the glow.
func add_light(node: Node2D, weight: float = 1.0, dynamic: bool = false, ref_energy: float = 1.0) -> void:
	if node == null:
		return
	_lights.append({"node": node, "weight": weight, "dynamic": dynamic, "ref": maxf(ref_energy, 0.001)})


func _light_strength(l: Dictionary) -> float:
	var node = l["node"]
	if node == null or not is_instance_valid(node) or not (node as Node2D).visible:
		return 0.0
	var w: float = l["weight"]
	if bool(l["dynamic"]) and node is Light2D:
		w *= clampf((node as Light2D).energy / float(l["ref"]), 0.0, 1.0)
	return w


func _process(_delta: float) -> void:
	if not enabled:
		for c in _casters:
			for s in c["pool"]:
				if is_instance_valid(s):
					(s as Sprite2D).visible = false
		return
	for c in _casters:
		_update_caster(c)


func _update_caster(c: Dictionary) -> void:
	var src = c["src"]
	if src == null or not is_instance_valid(src) or not (src as Sprite2D).visible:
		for s in c["pool"]:
			if is_instance_valid(s):
				(s as Sprite2D).visible = false
		return
	var spr := src as Sprite2D
	var sp: Vector2 = spr.global_position
	# Faked height: a lifted caster (the flying ship) pulls its shadows farther + fainter.
	var lift01 := 0.0
	if (c["lift_cb"] as Callable).is_valid():
		lift01 = clampf(float((c["lift_cb"] as Callable).call()), 0.0, 1.0)
	var extra: float = lift01 * float(c["lift_px"])
	var amul: float = lerpf(0.55, 1.0, 1.0 - lift01)
	var slot := 0
	for l in _lights:
		if slot >= max_per_caster:
			break
		var w := _light_strength(l)
		if w <= 0.01:
			continue
		var lp: Vector2 = (l["node"] as Node2D).global_position
		var d := sp - lp
		var dist := d.length()
		if dist < 0.01:
			continue
		var a := max_alpha * w * amul * clampf(1.0 - dist / maxf(falloff, 1.0), 0.0, 1.0)
		if a <= 0.004:
			continue
		var sh := _shadow(c, slot)
		_style(sh, spr)
		sh.modulate = Color(0.0, 0.0, 0.0, a)
		# Round only the OFFSET (not the absolute position) so the shadow shares the caster's sub-pixel
		# phase and rides it rigidly as the plate moves — no jiggle against a fractional-moving crate.
		sh.global_position = sp + ((d / dist) * (shadow_length + extra)).round()
		sh.visible = true
		slot += 1
	for j in range(slot, (c["pool"] as Array).size()):
		var s2 = c["pool"][j]
		if is_instance_valid(s2):
			(s2 as Sprite2D).visible = false


func _shadow(c: Dictionary, i: int) -> Sprite2D:
	var pool: Array = c["pool"]
	while pool.size() <= i:
		var s := Sprite2D.new()
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = int(c["z"])
		(c["parent"] as Node).add_child(s)
		pool.append(s)
	return pool[i]


# Mirror the caster's look as a flat black silhouette (no material — the body's damage shader etc. must
# NOT carry over). Parents here are unrotated/unscaled, so local rotation/scale == global.
func _style(sh: Sprite2D, src: Sprite2D) -> void:
	sh.texture = src.texture
	sh.hframes = src.hframes
	sh.vframes = src.vframes
	sh.frame = src.frame
	sh.flip_h = src.flip_h
	sh.flip_v = src.flip_v
	sh.rotation = src.rotation
	sh.scale = src.scale * (1.0 + softness)
