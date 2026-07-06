extends Node2D

# DeckLife — a reusable "living hangar deck" component (docs/deck_life_plan_2026-07-04.md). Add it as a
# child of any Node2D surface (the outpost plate now; a ship-select stage later), configure() it with a
# walkable bounds rect (in the surface's local space) + an optional ship anchor, then set_count(). It
# spawns wandering DeckCrew with drop shadows and, when the host calls react(kind), dispatches crew to
# the ship (repair/upgrade → weld up; buy/refill → deliver; sell/scrap → haul off).
#
# Surface-agnostic ON PURPOSE — it holds no reference to OutpostArrival / hangar_stage. Reactions are
# cosmetic and fire-and-forget; the host's shop logic never waits on them. Phase 0/1 = wander + basic
# dispatch; vehicles + welding FX land in later phases at the WORK state.

const DeckCrew = preload("res://scripts/screens/deck_crew.gd")
const DeckVehicle = preload("res://scripts/screens/deck_vehicle.gd")
const LIFTER_SCENE := "res://scenes/outpost/outpost_lifter.tscn"

# Suit palette for the placeholder crew (varied so the deck reads as a real crew, not clones).
const SUITS := [
	Color(0.86, 0.55, 0.20), Color(0.30, 0.56, 0.86), Color(0.62, 0.62, 0.68),
	Color(0.82, 0.34, 0.32), Color(0.42, 0.72, 0.42), Color(0.80, 0.78, 0.40),
]

const CARRY_FLANK := Vector2(3, 0)   # crew stand ±3px either side of a carried crate

var bounds: Rect2 = Rect2()
var ship_anchor: Vector2 = Vector2.INF   # local pos of the ship (for reactions); INF = no ship
var crew_speed: float = 0.8
var veh_speed: float = 1.6   # lifter drive speed (px/frame, a bit faster than crew)
var _crew: Array = []
var _crates: Array = []
var _carry = null            # active two-crew carry: {crate, a, b, target, phase} (one at a time)
var _lifter = null           # DeckVehicle (optional; outpost only)
var _lift_job = null         # active lifter run: {crew, crate, drop, phase, t} (one at a time)
var _rng := RandomNumberGenerator.new()
var _social_t: float = 6.0   # countdown to the next congregate / crate-visit
var _carry_t: float = 5.0    # countdown to the next crate-carry attempt
var _lift_t: float = 8.0     # countdown to the next lifter run


func configure(p_bounds: Rect2, p_ship_anchor: Vector2 = Vector2.INF, seed_v: int = 0) -> void:
	bounds = p_bounds
	ship_anchor = p_ship_anchor
	_rng.seed = seed_v if seed_v != 0 else 0x1234ABCD


# Show/hide + pause the whole deck (crew stop processing when off). Used while the plate flies in/out.
func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func set_count(n: int) -> void:
	n = clampi(n, 0, 24)
	while _crew.size() > n:
		var c = _crew.pop_back()
		if is_instance_valid(c):
			c.queue_free()
	while _crew.size() < n:
		_add_crew()


func set_speed(s: float) -> void:
	crew_speed = maxf(0.05, s)
	for c in _crew:
		if is_instance_valid(c):
			c.speed = crew_speed


func _add_crew() -> void:
	var c = DeckCrew.new()
	add_child(c)
	c.setup(bounds, crew_speed, SUITS[_rng.randi() % SUITS.size()], _rng.randi())
	_crew.append(c)


# Movable crate props for the crate-carry / walk-to-box behaviors.
func set_crate_count(n: int) -> void:
	n = clampi(n, 0, 12)
	while _crates.size() > n:
		var cr = _crates.pop_back()
		if is_instance_valid(cr):
			cr.queue_free()
	while _crates.size() < n:
		_add_crate()


func _add_crate() -> void:
	var cr := _make_crate()
	add_child(cr)
	cr.position = _rand_bounds_point()
	_crates.append(cr)


# A crate = a Node2D with a 4×4 box sprite + a shadow (both nearest, absolute z so they sit on the deck).
func _make_crate() -> Node2D:
	var root := Node2D.new()
	var sh := Sprite2D.new()
	sh.texture = _crate_shadow_tex()
	sh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sh.z_index = -6
	sh.z_as_relative = false
	sh.position = Vector2(0, 2)
	sh.modulate = Color(0, 0, 0, 0.4)
	root.add_child(sh)
	var b := Sprite2D.new()
	b.texture = _crate_tex()
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.z_index = -5
	b.z_as_relative = false
	root.add_child(b)
	return root


static func _crate_tex() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var body := Color(0.52, 0.38, 0.22)
	img.fill(body)
	var top := Color(0.66, 0.50, 0.30)
	var edge := Color(0.34, 0.24, 0.14)
	for x in 4:
		img.set_pixel(x, 0, top)
	for y in 4:
		img.set_pixel(0, y, edge)
		img.set_pixel(3, y, edge)
	return ImageTexture.create_from_image(img)


static func _crate_shadow_tex() -> ImageTexture:
	var img := Image.create(5, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(4, 0, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _rand_bounds_point() -> Vector2:
	return Vector2(
		round(_rng.randf_range(bounds.position.x, bounds.end.x)),
		round(_rng.randf_range(bounds.position.y, bounds.end.y)))


func _pick_free_crew():
	var free := []
	for c in _crew:
		if is_instance_valid(c) and not c.pinned:
			free.append(c)
	return free[_rng.randi() % free.size()] if not free.is_empty() else null


# A crate not already reserved by an active carry or lifter run.
func _crate_busy(cr) -> bool:
	if _carry != null and _carry.get("crate") == cr:
		return true
	if _lift_job != null and _lift_job.get("crate") == cr:
		return true
	return false


func _pick_free_crate():
	var free := []
	for cr in _crates:
		if is_instance_valid(cr) and not _crate_busy(cr):
			free.append(cr)
	return free[_rng.randi() % free.size()] if not free.is_empty() else null


# Force a crate carry now (dev/lab). No-op if one's already running or there's nothing to carry.
func carry_now() -> void:
	if _carry == null:
		_try_start_carry()


# Ambient life: congregate / visit-a-crate on the social timer; run the crate-carry on its own timer.
func _process(delta: float) -> void:
	_social_t -= delta
	if _social_t <= 0.0:
		_social_t = _rng.randf_range(7.0, 16.0)
		if _rng.randf() < 0.5:
			_congregate()
		else:
			_visit_crate()
	if _carry == null:
		_carry_t -= delta
		if _carry_t <= 0.0:
			_carry_t = _rng.randf_range(9.0, 18.0)
			_try_start_carry()
	else:
		_tick_carry(delta)
	if _lifter != null and is_instance_valid(_lifter):
		if _lift_job == null:
			_lift_t -= delta
			if _lift_t <= 0.0:
				_lift_t = _rng.randf_range(12.0, 22.0)
				_try_start_lift_job()
		else:
			_tick_lift_job(delta)


# Walk-to-boxes: a free crew strolls over to a crate and looks it over.
func _visit_crate() -> void:
	var cr = _pick_free_crate()
	var c = _pick_free_crew()
	if cr != null and c != null:
		c.go_to(cr.position + Vector2(_rng.randf_range(-4, 4), 4), _rng.randf_range(1.5, 3.5), false)


# --- Two-crew crate carry -------------------------------------------------
# Two crew flank a crate (one either side), lift it, and walk it together to a new spot. DeckLife drives
# both crew (pinned) + the crate directly so they move as one rigid unit.

func _try_start_carry() -> void:
	if _crates.is_empty():
		return
	var free := []
	for c in _crew:
		if is_instance_valid(c) and not c.pinned:
			free.append(c)
	if free.size() < 2:
		return
	var crate = _pick_free_crate()
	if crate == null:
		return
	free[0].set_pinned(true)
	free[1].set_pinned(true)
	_carry = {"crate": crate, "a": free[0], "b": free[1], "target": _rand_bounds_point(), "phase": "approach"}


func _tick_carry(delta: float) -> void:
	if _carry == null:
		return
	var crate = _carry["crate"]
	var a = _carry["a"]
	var b = _carry["b"]
	if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
		_end_carry()
		return
	var spd := crew_speed * 60.0 * delta
	if _carry["phase"] == "approach":
		# Each crew walks to its side of the crate; once both are set, lift.
		var da := _move_to(a, crate.position - CARRY_FLANK, spd)
		var db := _move_to(b, crate.position + CARRY_FLANK, spd)
		if da and db:
			_carry["phase"] = "carry"
	else:
		# Carry: move the crate to the target (a touch slower); pin the crew to its flanks.
		var arrived := _move_to(crate, _carry["target"], spd * 0.7)
		a.position = crate.position - CARRY_FLANK
		b.position = crate.position + CARRY_FLANK
		if arrived:
			_end_carry()


func _move_to(node, target: Vector2, spd: float) -> bool:
	var to: Vector2 = target - node.position
	var d := to.length()
	if d <= maxf(spd, 0.5):
		node.position = target
		return true
	node.position = (node.position + to / d * spd).round()
	return false


func _end_carry() -> void:
	if _carry != null:
		if is_instance_valid(_carry["a"]):
			_carry["a"].set_pinned(false)
		if is_instance_valid(_carry["b"]):
			_carry["b"].set_pinned(false)
	_carry = null


# --- Lifter run (a crew boards the hover lifter → it moves a crate) --------
# A crewman walks to the parked lifter, boards (hides), the reactor powers on, the lifter flies to a
# crate, carries it to a new spot, sets it down, returns home, powers off, and the crew disembarks.

const LIFT_CARRY_OFF := Vector2(0, 1)   # the crate rides just under the lifter centre


# Spawn/remove the lifter (outpost only — ship-select won't have one). Parks it at a bounds edge.
func set_lifter(on: bool) -> void:
	if on:
		if _lifter == null or not is_instance_valid(_lifter):
			_lifter = DeckVehicle.new()
			add_child(_lifter)
			var lhome := Vector2(round(bounds.position.x + 24.0), round(bounds.get_center().y))
			_lifter.setup(LIFTER_SCENE, lhome)
	elif _lifter != null and is_instance_valid(_lifter):
		_end_lift_job()
		_lifter.queue_free()
		_lifter = null


# Force a lifter run now (dev/lab).
func lifter_run_now() -> void:
	if _lift_job == null:
		_try_start_lift_job()


func _try_start_lift_job() -> void:
	if _lifter == null or not is_instance_valid(_lifter) or _lift_job != null:
		return
	var crate = _pick_free_crate()
	var crew = _pick_free_crew()
	if crate == null or crew == null:
		return
	crew.set_pinned(true)
	crew.visible = true
	_lift_job = {"crew": crew, "crate": crate, "drop": _rand_bounds_point(), "phase": "board", "t": 0.0}


func _tick_lift_job(delta: float) -> void:
	if _lift_job == null:
		return
	var crew = _lift_job["crew"]
	var crate = _lift_job["crate"]
	if not (is_instance_valid(crew) and is_instance_valid(crate) and is_instance_valid(_lifter)):
		_end_lift_job()
		return
	var vspd := veh_speed * 60.0 * delta
	var cspd := crew_speed * 60.0 * delta
	match _lift_job["phase"]:
		"board":
			if _move_to(crew, _lifter.home, cspd):
				crew.visible = false
				_lifter.set_powered(true)
				_lift_job["phase"] = "to_crate"
		"to_crate":
			if _move_to(_lifter, crate.position - LIFT_CARRY_OFF, vspd):
				_lift_job["phase"] = "lift"
				_lift_job["t"] = 0.5
		"lift":
			_lift_job["t"] -= delta
			crate.position = _lifter.position + LIFT_CARRY_OFF
			if _lift_job["t"] <= 0.0:
				_lift_job["phase"] = "haul"
		"haul":
			var at := _move_to(_lifter, _lift_job["drop"], vspd)
			crate.position = _lifter.position + LIFT_CARRY_OFF
			if at:
				_lift_job["phase"] = "drop"
				_lift_job["t"] = 0.4
		"drop":
			_lift_job["t"] -= delta
			if _lift_job["t"] <= 0.0:
				_lift_job["phase"] = "return"
		"return":
			if _move_to(_lifter, _lifter.home, vspd):
				_lifter.set_powered(false)
				crew.visible = true
				crew.position = _lifter.home + Vector2(5, 4)
				_lift_job["phase"] = "done"
				_lift_job["t"] = 0.2
		_:
			_lift_job["t"] -= delta
			if _lift_job["t"] <= 0.0:
				_end_lift_job()


func _end_lift_job() -> void:
	if _lift_job != null and is_instance_valid(_lift_job["crew"]):
		_lift_job["crew"].visible = true
		_lift_job["crew"].set_pinned(false)
	if _lifter != null and is_instance_valid(_lifter):
		_lifter.set_powered(false)
	_lift_job = null


# The reactive hook the host calls after a shop action. Cosmetic; a no-op if there's no ship anchor.
# repair/upgrade weld the ship (sparks + arc); buy/refill is a plain work pause; sell/scrap hauls off.
func react(kind: String, _ctx: Dictionary = {}) -> void:
	match kind:
		"upgrade":
			_dispatch_to_ship(2, 2.6, true)
		"repair":
			_dispatch_to_ship(1, 2.4, true)
		"buy", "refill":
			_dispatch_to_ship(1, 1.3, false)
		"sell", "scrap":
			_dispatch_leave(1)


# Send up to `n` crew to the ship to work for `work_secs` (weld=true → sparks + arc).
func _dispatch_to_ship(n: int, work_secs: float, weld: bool) -> void:
	if ship_anchor == Vector2.INF:
		return
	var picked := 0
	for c in _crew:
		if picked >= n:
			break
		if is_instance_valid(c) and not c.pinned:
			var off := Vector2(_rng.randf_range(-11, 11), _rng.randf_range(4, 13))
			c.go_to(ship_anchor + off, work_secs, weld)
			picked += 1


# 2–3 crew gather at a shared spot and pause (a little group chat).
func _congregate() -> void:
	if _crew.size() < 2:
		return
	var anchor = _crew[_rng.randi() % _crew.size()]
	if not is_instance_valid(anchor):
		return
	var meet: Vector2 = anchor.position
	var want := 2 + (_rng.randi() % 2)
	var picked := 0
	for c in _crew:
		if picked >= want:
			break
		if is_instance_valid(c) and not c.pinned:
			var off := Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-5, 5))
			c.go_to(_clamp_to_bounds(meet + off), _rng.randf_range(2.0, 4.5), false)
			picked += 1


func _clamp_to_bounds(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, bounds.position.x, bounds.end.x),
		clampf(p.y, bounds.position.y, bounds.end.y))


# Send `n` crew off toward a deck edge (hauling a scrapped/sold part away).
func _dispatch_leave(n: int) -> void:
	var picked := 0
	for c in _crew:
		if picked >= n:
			break
		if is_instance_valid(c) and not c.pinned:
			var ex := bounds.position.x if c.position.x < bounds.get_center().x else bounds.end.x
			c.go_to(Vector2(ex, c.position.y), 1.2)
			picked += 1


# Clear the deck: every crew walks to the nearest horizontal edge (used on departure).
func scatter() -> void:
	for c in _crew:
		if is_instance_valid(c):
			var ex := bounds.position.x if c.position.x < bounds.get_center().x else bounds.end.x
			c.leave(Vector2(ex, c.position.y))
