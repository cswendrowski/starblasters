extends Area2D
class_name ShieldDrone

# Intercept drone — the Intercept Drones module's screen. 2026-07-16 behavior pass (Roman):
#
#   FORMATION   A forward ARC over the ship's nose (was a full orbit). Combat drones own
#               the left/right flanks (autonomous_drone.gd), intercept drones own the
#               front — the two systems never overlap or jumble. Slots spread evenly
#               across the arc with a small phase-offset sway so the screen reads alive.
#   INTERCEPT   Each drone scans for the nearest incoming enemy bullet near the player
#               and DARTS at it (fast damped spring, leashed to its slot) — it visibly
#               moves to take the hit for the ship, and the lunge genuinely intercepts.
#   I-FRAMES    Absorbing a hit starts a short invulnerability (like the ship shield's
#               per-hit i-frame): contacts during it are soaked FREE, so a bullet
#               cluster can't strip a drone in one frame. White flash tell.
#   DAMAGE TELL Progressive char tint per hit + an impact-spark burst on every hit + a
#               periodic spark sputter on the LAST hit — you can read each drone's
#               remaining hits at a glance. (The polygon placeholder art can't host the
#               sprite damage_noise material; when dedicated sprite art lands, install
#               that shader here and drive `sensitivity` = damage_fraction instead.)
#   RECALL      While the player runs a damage-preventing Shift mode (Phase/Rush/Thief —
#               player.defense_mode_active()), drones tuck in tight behind the ship,
#               go non-colliding + dim, and spend no hits; they redeploy when it ends.

# (ImpactFx is a global class_name — used directly for the spark bursts.)

# Formation (set by the Intercept Drones part).
@export var arc_radius: float = 24.0
@export var arc_spread_deg: float = 110.0
@export var max_hits: int = 2

const SWAY_DEG := 5.0             # per-drone idle sway amplitude along the arc
const SWAY_HZ := 0.55
const SCAN_RADIUS := 56.0         # bullets within this range of the PLAYER are threats
const LEASH := 16.0               # max dart distance away from the arc slot
const SPRING := 70.0              # damped-spring stiffness (swift — reads as a lunge)
const DAMP := 11.0
const MAX_SPEED := 340.0
const HIT_IFRAME := 0.35          # free-soak window after an absorbed hit
const FLASH_TIME := 0.16
const RECALL_OFFSET := Vector2(0, 9.0)   # tuck spot: tight behind the ship
const RECALL_ALPHA := 0.45
const SPUTTER_INTERVAL := 0.7     # spark cadence on the last hit
const CHAR_COLOR := Color(0.52, 0.38, 0.36)   # fully-damaged tint (charred)
const SPARK_COLOR := Color(1.0, 0.75, 0.35)

var _player: Node2D = null
var _index: int = 0
var _count: int = 1
var _hits: int = 0
var _dying: bool = false
var _bound: bool = false
var _vel: Vector2 = Vector2.ZERO
var _sway_t: float = 0.0
var _iframe_t: float = 0.0
var _flash_t: float = 0.0
var _sputter_t: float = 0.0
var _recalled: bool = false


func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


# Called (deferred) by the Intercept Drones module / legacy drone_bits part.
func bind_player(player: Node2D, index: int, count: int, hp: int) -> void:
	_player = player
	_bound = true
	_index = index
	_count = maxi(1, count)
	max_hits = maxi(1, hp)
	_hits = 0
	# Random sway phase per slot so the arc doesn't breathe in lockstep.
	_sway_t = float(index) * 1.7
	if player != null and is_instance_valid(player):
		global_position = player.global_position + _slot_offset()


func _process(delta: float) -> void:
	if _dying:
		return
	if _player == null or not is_instance_valid(_player):
		if _bound:
			queue_free()
		return
	_sway_t += delta
	_iframe_t = maxf(0.0, _iframe_t - delta)
	_flash_t = maxf(0.0, _flash_t - delta)
	_tick_recall()
	# Where this drone wants to be: recall tuck > bullet intercept > arc slot.
	var slot: Vector2 = _player.global_position + _slot_offset()
	var desired: Vector2 = slot
	if _recalled:
		desired = _player.global_position + RECALL_OFFSET + Vector2(float(_index - (_count - 1) * 0.5) * 7.0, 0.0)
	else:
		var threat: Node2D = _nearest_incoming_bullet()
		if threat != null:
			# Lunge at the bullet, leashed to the slot so the formation holds.
			var to_threat: Vector2 = threat.global_position - slot
			desired = slot + to_threat.limit_length(LEASH)
	# Swift damped spring (reads as a dart, settles without wobble).
	var to_desired: Vector2 = desired - global_position
	_vel += (to_desired * SPRING - _vel * DAMP) * delta
	if _vel.length() > MAX_SPEED:
		_vel = _vel.normalized() * MAX_SPEED
	global_position += _vel * delta
	_update_visual()
	# Last-hit tell: sputter sparks so "one more hit pops it" is readable.
	if not _recalled and max_hits - _hits == 1:
		_sputter_t -= delta
		if _sputter_t <= 0.0:
			_sputter_t = SPUTTER_INTERVAL + randf() * 0.3
			var jitter := Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
			ImpactFx.spawn(get_parent(), global_position + jitter, SPARK_COLOR)


# Arc slot for this drone: evenly spread across a forward fan centred on the ship's
# nose, plus the idle sway. (Combat drones flank at y=0 — this arc stays above it.)
func _slot_offset() -> Vector2:
	var spread: float = deg_to_rad(arc_spread_deg)
	var frac: float = 0.5 if _count <= 1 else float(_index) / float(_count - 1)
	var ang: float = -PI / 2.0 + (frac - 0.5) * spread
	ang += deg_to_rad(SWAY_DEG) * sin(_sway_t * TAU * SWAY_HZ)
	return Vector2(cos(ang), sin(ang)) * arc_radius


# Recall in/out on the player's damage-preventing modes. Collision toggles are
# deferred (physics-safe); the dim alpha is handled in _update_visual.
func _tick_recall() -> void:
	var want: bool = _player.has_method("defense_mode_active") and _player.defense_mode_active()
	if want == _recalled:
		return
	_recalled = want
	set_deferred("monitoring", not _recalled)
	set_deferred("monitorable", not _recalled)


# Nearest enemy bullet that's near the player and actually inbound. Checked from the
# DRONE's position so multiple drones naturally split across multiple bullets.
func _nearest_incoming_bullet() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	var ppos: Vector2 = _player.global_position
	for grp in ["enemy_bullets", "bullets"]:
		for b in tree.get_nodes_in_group(grp):
			if not is_instance_valid(b) or not (b is Node2D):
				continue
			if (b.global_position - ppos).length() > SCAN_RADIUS:
				continue
			# Skip bullets flying AWAY from the player (duck-typed — bullets without a
			# velocity field are assumed inbound).
			if "velocity" in b:
				var v: Vector2 = b.velocity
				if v.length_squared() > 1.0 and v.dot(ppos - b.global_position) <= 0.0:
					continue
			var d: float = (b.global_position - global_position).length_squared()
			if d < best_d:
				best_d = d
				best = b
	return best


# Bullet / collision contact. During the i-frame window contacts are soaked for free
# (the bullet still dies on us — same feel as the ship shield's per-hit i-frame).
func _on_area_entered(area: Area2D) -> void:
	if _dying or _recalled:
		return
	if area == _player:
		return
	if area.is_in_group("shield_drones") or area.is_in_group("player_drones") or area.is_in_group("player"):
		return
	if not (area.is_in_group("enemies") or area.is_in_group("enemy_bullets") or area.is_in_group("bullets")):
		return
	_absorb_hit()


# Public — called by ShieldDrone-aware bullets. Returns true when the drone popped.
func take_hit(_damage: int = 1) -> bool:
	if _dying or _recalled:
		return false
	_absorb_hit()
	return _dying


func _absorb_hit() -> void:
	if _iframe_t > 0.0:
		return   # free soak — no hit consumed
	_hits += 1
	_iframe_t = HIT_IFRAME
	_flash_t = FLASH_TIME
	ImpactFx.spawn(get_parent(), global_position, SPARK_COLOR)
	if _hits >= max_hits:
		_explode()


# Damage char + hit flash + recall dim, combined into one modulate write.
func _update_visual() -> void:
	var frac: float = clampf(float(_hits) / float(maxi(1, max_hits)), 0.0, 1.0)
	var col: Color = Color.WHITE.lerp(CHAR_COLOR, frac * 0.85)
	if _flash_t > 0.0:
		col = col.lerp(Color(2.0, 2.0, 2.0), clampf(_flash_t / FLASH_TIME, 0.0, 1.0))
	col.a = RECALL_ALPHA if _recalled else 1.0
	modulate = col


func _explode() -> void:
	if _dying:
		return
	_dying = true
	var ExplosionFxCls = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFxCls:
		ExplosionFxCls.play(global_position, 0.5, false)
	ImpactFx.spawn(get_parent(), global_position, SPARK_COLOR)
	queue_free()
