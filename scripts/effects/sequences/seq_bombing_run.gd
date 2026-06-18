extends "res://scripts/effects/sequences/sequence_player.gd"

# Bombing Run (Roman 2026-06-17) — an in-band bomber / wing TRANSITIONS OUT of the playfield,
# becomes an overhead SHADOW (its own body sprite, black @ 40%), and carpet-bombs the lanes.
# A variant of the missile-cruiser area attack: non-overlapping red telegraph markers are laid
# down a lane PATTERN, then detonated row-by-row in a sweep — top→bottom or bottom→top — with
# the shadow riding the detonation front.
#
# Phases (one TARGET, driven the whole way):
#   ASCEND  — the target flies up and off the top while every telegraph pulses (the lead warning).
#   SWEEP   — the shadow rides the detonation direction at shadow_speed; each row detonates as the
#             shadow crosses it (AoE damage to "player" + a 1× explosion, via MissileSalvo).
#   RETURN  — re-enter (drop the target back into its hold band) or exit (leave it gone).
#
# Lane patterns (Lanes.lane_center i): left-3 = 0/1/2, right-3 = 4/5/6, middle-3 = 2/3/4,
# every-other = 0/2/4/6. aoe_radius ~12 keeps adjacent lanes (pitch 30) non-overlapping.
#
# Reuses MissileSalvo.TelegraphCircle + MissileSalvo.detonate_aoe. Telegraphs / shadow / explosions
# parent to get_parent() (the sequence's world sibling) so they render in the right viewport in BOTH
# the Sequence Lab SubViewport and live combat — and all positions are global, so a parent transform
# doesn't matter. With no "player" in the lab, detonate_aoe is pure VFX (the look/AoE tuning surface).

const PH_ASCEND := 0
const PH_SWEEP := 1
const PH_RETURN := 2

const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.40)
const SHADOW_Z := 20
const ASCEND_EXIT_Y := -30.0   # target is "off the top" at/above this Y
const SHADOW_LEAD := 36.0       # shadow starts this far before the first row / exits this far past the last
const ROW_Y_MIN := 48.0         # topmost bomb row (just inside Zones.ENTRY_END = 40)
const ROW_Y_MAX := 188.0        # bottommost bomb row (just inside Zones.DEPARTURE_START = 195)

var _phase: int = PH_ASCEND
var _start_pos: Vector2 = Vector2.ZERO
var _direction_down: bool = true
var _aoe_radius: float = 12.0
var _damage: int = 1
var _shadow_speed: float = 120.0
var _ascend_speed: float = 200.0
var _telegraph_lead: float = 1.0
var _return_mode: int = 0       # 0 = re-enter hold band, 1 = exit (stay gone)
var _pattern_center_x: float = 240.0
var _rows: Array = []           # [{y, bombs:[{pos, tel}], done}]
var _shadow: Sprite2D = null


static func knob_schema() -> Array:
	return [
		{"key": "pattern", "label": "Pattern (0L3/1R3/2Mid/3Alt)", "min": 0.0, "max": 3.0, "step": 1.0, "def": 0.0},
		{"key": "direction", "label": "Direction (0=T→B/1=B→T)", "min": 0.0, "max": 1.0, "step": 1.0, "def": 0.0},
		{"key": "bombs_per_lane", "label": "Bombs per lane", "min": 1.0, "max": 6.0, "step": 1.0, "def": 4.0},
		{"key": "telegraph_time", "label": "Telegraph lead (s)", "min": 0.2, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "shadow_speed", "label": "Shadow speed (px/s)", "min": 30.0, "max": 300.0, "step": 5.0, "def": 120.0},
		{"key": "ascend_speed", "label": "Ascend speed (px/s)", "min": 60.0, "max": 400.0, "step": 10.0, "def": 200.0},
		{"key": "aoe_radius", "label": "AoE radius (px)", "min": 6.0, "max": 18.0, "step": 1.0, "def": 12.0},
		{"key": "damage", "label": "Damage", "min": 1.0, "max": 5.0, "step": 1.0, "def": 1.0},
		{"key": "return_mode", "label": "Return (0=re-enter/1=exit)", "min": 0.0, "max": 1.0, "step": 1.0, "def": 0.0},
	]


func _begin() -> void:
	if target == null or not is_instance_valid(target):
		_finish()
		return
	_start_pos = target.global_position
	var pattern: int = int(round(k("pattern", 0.0)))
	_direction_down = int(round(k("direction", 0.0))) == 0
	_aoe_radius = k("aoe_radius", 12.0)
	_damage = int(round(k("damage", 1.0)))
	_shadow_speed = k("shadow_speed", 120.0)
	_ascend_speed = k("ascend_speed", 200.0)
	_telegraph_lead = k("telegraph_time", 1.0)
	_return_mode = int(round(k("return_mode", 0.0)))

	var lanes: Array = _pattern_lanes(pattern)
	var sum_x: float = 0.0
	for li in lanes:
		sum_x += Lanes.lane_center(int(li))
	_pattern_center_x = sum_x / float(lanes.size())

	# Bomb rows down the engagement band, ordered into the sweep direction.
	var ys: Array = _row_ys(maxi(1, int(round(k("bombs_per_lane", 4.0)))))
	if not _direction_down:
		ys.reverse()

	# Lay a telegraph at every row × lane.
	var world: Node = _world()
	_rows.clear()
	for ry in ys:
		var bombs: Array = []
		for li in lanes:
			var pos := Vector2(Lanes.lane_center(int(li)), float(ry))
			var tel := MissileSalvo.TelegraphCircle.new()
			tel.setup(pos, _aoe_radius)
			world.add_child(tel)
			bombs.append({"pos": pos, "tel": tel})
		_rows.append({"y": float(ry), "bombs": bombs, "done": false})

	# Overhead shadow, parked before the first row until the sweep begins.
	_shadow = _make_shadow()
	if _shadow != null:
		var start_y: float = float(ys[0]) + (-SHADOW_LEAD if _direction_down else SHADOW_LEAD)
		_shadow.global_position = Vector2(_pattern_center_x, start_y)
		world.add_child(_shadow)

	_phase = PH_ASCEND


func _on_tick(t: float, delta: float) -> void:
	match _phase:
		PH_ASCEND:
			_tick_ascend(t, delta)
		PH_SWEEP:
			_tick_sweep(delta)
		PH_RETURN:
			_tick_return(delta)


# ---- ASCEND: target flies up + off the top; telegraphs pulse the lead warning ----
func _tick_ascend(t: float, delta: float) -> void:
	if is_instance_valid(target):
		target.global_position += Vector2(0.0, -_ascend_speed * delta)
	var ascended: bool = (not is_instance_valid(target)) or target.global_position.y <= ASCEND_EXIT_Y
	if ascended and t >= _telegraph_lead:
		if is_instance_valid(target):
			target.visible = false
		_phase = PH_SWEEP


# ---- SWEEP: shadow rides the detonation front; rows detonate as it crosses them ----
func _tick_sweep(delta: float) -> void:
	var dir_sign: float = 1.0 if _direction_down else -1.0
	if is_instance_valid(_shadow):
		_shadow.global_position += Vector2(0.0, dir_sign * _shadow_speed * delta)
	var shadow_y: float = _shadow.global_position.y if is_instance_valid(_shadow) else (dir_sign * 1.0e9)

	var pending := false
	for row in _rows:
		if row["done"]:
			continue
		var reached: bool = (shadow_y >= row["y"]) if _direction_down else (shadow_y <= row["y"])
		if reached:
			_detonate_row(row)
			row["done"] = true
		else:
			pending = true

	var off_edge: bool = (shadow_y > Playfield.Y_MAX + SHADOW_LEAD) if _direction_down else (shadow_y < Playfield.Y_MIN - SHADOW_LEAD)
	if not pending and off_edge:
		_phase = PH_RETURN


func _detonate_row(row: Dictionary) -> void:
	var world: Node = _world()
	var tree: SceneTree = get_tree()
	for b in row["bombs"]:
		MissileSalvo.detonate_aoe(b["pos"], _aoe_radius, _damage, tree, world)
		var tel: Node = b["tel"]
		if tel != null and is_instance_valid(tel):
			tel.queue_free()


# ---- RETURN: drop the target back into its hold band, or leave it gone ----
func _tick_return(delta: float) -> void:
	if is_instance_valid(_shadow):
		_shadow.queue_free()
		_shadow = null
	if _return_mode == 1 or not is_instance_valid(target):
		if is_instance_valid(target):
			target.visible = true
		_finish()
		return
	if not target.visible:
		target.visible = true
		target.global_position = Vector2(_start_pos.x, ASCEND_EXIT_Y)
	target.global_position = target.global_position.move_toward(_start_pos, _ascend_speed * delta)
	if target.global_position.distance_to(_start_pos) <= 1.0:
		target.global_position = _start_pos
		_finish()


# ---- Helpers --------------------------------------------------------------

func _pattern_lanes(pattern: int) -> Array:
	match pattern:
		0: return [0, 1, 2]      # left 3 adjacent
		1: return [4, 5, 6]      # right 3 adjacent
		2: return [2, 3, 4]      # middle 3
		3: return [0, 2, 4, 6]   # every other
		_: return [2, 3, 4]


func _row_ys(n: int) -> Array:
	var ys: Array = []
	if n <= 1:
		ys.append((ROW_Y_MIN + ROW_Y_MAX) * 0.5)
		return ys
	var span: float = ROW_Y_MAX - ROW_Y_MIN
	for i in n:
		ys.append(ROW_Y_MIN + span * (float(i) / float(n - 1)))
	return ys


func _make_shadow() -> Sprite2D:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return null
	var sh := Sprite2D.new()
	sh.texture = sprite.texture
	sh.hframes = sprite.hframes
	sh.vframes = sprite.vframes
	sh.frame = sprite.frame
	sh.region_enabled = sprite.region_enabled
	sh.region_rect = sprite.region_rect
	sh.flip_h = sprite.flip_h
	sh.flip_v = sprite.flip_v
	sh.centered = sprite.centered
	sh.offset = sprite.offset
	var tscale: Vector2 = target.scale if is_instance_valid(target) else Vector2.ONE
	sh.scale = tscale * sprite.scale
	sh.modulate = SHADOW_COLOR
	sh.z_index = SHADOW_Z
	sh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sh


# The sequence's world sibling (the stage in the lab, the enemy container in combat). Positions are
# global, so a non-identity parent transform is harmless; this only picks the right VIEWPORT.
func _world() -> Node:
	return get_parent() if get_parent() != null else target


func _cleanup() -> void:
	if is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = null
	for row in _rows:
		for b in row["bombs"]:
			var tel: Node = b["tel"]
			if tel != null and is_instance_valid(tel):
				tel.queue_free()
	_rows.clear()


func _finish() -> void:
	_cleanup()
	super._finish()


func _exit_tree() -> void:
	_cleanup()
