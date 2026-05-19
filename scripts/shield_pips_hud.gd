extends HBoxContainer

# HUD shield-pip strip. Replaces the old shield ProgressBar.
#
# Sprite strip layout (shield_pips.png, 48×16, three 16×16 frames):
#   Frame 0 — full / charged pip (bright)
#   Frame 1 — recharging pip art (drawn growing from the bottom up while
#             a charge is regenerating)
#   Frame 2 — empty / expended pip
#
# Behavior per Roman, 2026-05-17:
#   - One pip per max_shield. The leftmost N pips are charged where N =
#     current shield charges.
#   - The first not-yet-full pip animates a "fill from bottom up" using
#     frame 1 art, sized to (16, h) where h grows over shield_recharge_seconds.
#   - When the pip finishes filling: flash white briefly, then swap to
#     frame 0 (charged).
#   - When the player loses a charge (shield_changed fires with a lower
#     value): flash the rightmost previously-charged pip white, then
#     swap it to frame 2 (empty).

const PIP_TEX = preload("res://graphics/ui/shield_pips.png")
const PIP_SIZE: int = 16
const SPACING: int = 2
const FRAME_FULL: int = 0
const FRAME_RECHARGING: int = 1
const FRAME_EMPTY: int = 2

var _player: Node = null
var _max: int = 0
var _shield: int = 0
# Per-pip Controls. Each entry: {root: Control, bg: TextureRect, fill: TextureRect, full: TextureRect}
var _pips: Array = []
# Fraction (0..1) of the currently-recharging pip's fill height.
var _recharge_frac: float = 0.0
var _flash_tw: Tween = null


func _ready() -> void:
	add_theme_constant_override("separation", SPACING)
	custom_minimum_size = Vector2(0, PIP_SIZE)


func bind_player(p: Node) -> void:
	_player = p
	if p and p.has_signal("shield_changed"):
		if not p.shield_changed.is_connected(_on_shield_changed):
			p.shield_changed.connect(_on_shield_changed)
	if p:
		_max = int(p.max_shield)
		_shield = int(p.shield)
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_pips.clear()
	for i in _max:
		var pip := _make_pip()
		add_child(pip["root"])
		_pips.append(pip)
	_refresh_pip_states(false)
	_recharge_frac = 0.0


func _make_pip() -> Dictionary:
	# Each pip is a 16×16 Control with three stacked TextureRects.
	# Visibility per-pip drives which state is shown; the recharging
	# fill is a TextureRect with a region that grows from the bottom up.
	var root := Control.new()
	root.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
	root.size = Vector2(PIP_SIZE, PIP_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Empty pip background (always present, visible only when state ≠ FULL).
	var bg := TextureRect.new()
	bg.texture = _atlas(FRAME_EMPTY)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	# Recharging fill — a TextureRect using an AtlasTexture sub-region of
	# frame 1 that shows the bottom h pixels (h grows from 0 → 16). We
	# anchor it to the bottom so the fill appears to rise.
	var fill := TextureRect.new()
	fill.texture = _atlas(FRAME_RECHARGING)
	fill.stretch_mode = TextureRect.STRETCH_KEEP
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_top = 1.0
	fill.anchor_right = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 0
	fill.offset_top = 0
	fill.offset_right = PIP_SIZE
	fill.offset_bottom = 0
	fill.visible = false
	root.add_child(fill)
	# Charged pip — visible only when this slot is at full.
	var full := TextureRect.new()
	full.texture = _atlas(FRAME_FULL)
	full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full.stretch_mode = TextureRect.STRETCH_KEEP
	full.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full.visible = false
	root.add_child(full)
	return {"root": root, "bg": bg, "fill": fill, "full": full}


static var _atlas_cache: Array = []
static func _atlas(idx: int) -> Texture2D:
	if _atlas_cache.is_empty():
		_atlas_cache.resize(3)
		for i in 3:
			var at := AtlasTexture.new()
			at.atlas = PIP_TEX
			at.region = Rect2(i * PIP_SIZE, 0, PIP_SIZE, PIP_SIZE)
			_atlas_cache[i] = at
	return _atlas_cache[clamp(idx, 0, 2)]


# Set the visible state of every pip given current `_shield` count.
func _refresh_pip_states(animate_fill_reset: bool = true) -> void:
	for i in _pips.size():
		var pip: Dictionary = _pips[i]
		var full_rect: TextureRect = pip["full"]
		var fill_rect: TextureRect = pip["fill"]
		var bg_rect: TextureRect = pip["bg"]
		if i < _shield:
			full_rect.visible = true
			fill_rect.visible = false
			bg_rect.visible = false
		else:
			full_rect.visible = false
			bg_rect.visible = true
			fill_rect.visible = false
	# If shield < max, the first not-yet-full pip is the recharging one.
	if _shield < _pips.size():
		var idx: int = _shield
		var pip2: Dictionary = _pips[idx]
		pip2["fill"].visible = true
		if animate_fill_reset:
			_recharge_frac = 0.0
		_apply_fill_height(pip2["fill"], _recharge_frac)


# Drive the recharging-pip fill height. Called every frame from _process
# so the fill grows smoothly even when the player is mid-combat.
func _apply_fill_height(fill_rect: TextureRect, frac: float) -> void:
	var h: float = clamp(frac, 0.0, 1.0) * float(PIP_SIZE)
	# Bottom-anchored: offset_top is negative h, offset_bottom = 0.
	fill_rect.offset_top = -h
	fill_rect.offset_bottom = 0
	# Grow the atlas region from the bottom so only the filled portion of
	# the recharging art renders.
	var at := fill_rect.texture as AtlasTexture
	if at:
		at.region = Rect2(FRAME_RECHARGING * PIP_SIZE, PIP_SIZE - h, PIP_SIZE, h)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# When the shield is below max, drive the fill fraction using the
	# player's ShieldRegenTimer remaining time. Player.shield_recharge_seconds
	# is the full-tick period.
	if _shield >= _max:
		return
	var period: float = float(_player.shield_recharge_seconds) if "shield_recharge_seconds" in _player else 30.0
	# Read the timer's time_left to compute fraction filled. When the
	# timer isn't started yet (shield == max), there's nothing to draw.
	var t_left: float = period
	if _player.has_node("ShieldRegenTimer"):
		var t = _player.get_node("ShieldRegenTimer")
		if t and t.is_stopped() == false:
			t_left = float(t.time_left)
	_recharge_frac = clamp(1.0 - (t_left / period), 0.0, 1.0)
	if _shield < _pips.size():
		_apply_fill_height(_pips[_shield]["fill"], _recharge_frac)


func _on_shield_changed(_max_value, value) -> void:
	var prev: int = _shield
	var new_v: int = int(value)
	var new_max: int = int(_max_value)
	if new_max != _max:
		_max = new_max
		_shield = new_v
		_rebuild()
		return
	_shield = new_v
	# Charge drained — flash the rightmost previously-filled pip and
	# swap it to empty.
	if new_v < prev:
		for i in range(prev - 1, new_v - 1, -1):
			_flash_pip(i, true)
	# Charge restored — flash the just-filled pip and swap it to full.
	elif new_v > prev:
		for i in range(prev, new_v):
			_flash_pip(i, false)
	_refresh_pip_states(false)


# Brief flash on a pip when it transitions. `drained` = true flashes from
# full → empty, false flashes from recharging → full.
func _flash_pip(idx: int, drained: bool) -> void:
	if idx < 0 or idx >= _pips.size():
		return
	var pip: Dictionary = _pips[idx]
	var root: Control = pip["root"]
	root.modulate = Color(1.6, 1.6, 1.6, 1.0) if drained else Color(1.4, 2.0, 1.6, 1.0)
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_property(root, "modulate", Color(1, 1, 1, 1), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
