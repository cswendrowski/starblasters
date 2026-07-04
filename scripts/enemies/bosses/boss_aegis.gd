extends "res://scripts/enemies/bosses/boss_base.gd"

# Aegis (formerly Sentinel) — sector 2-3 multi-part turret. Identity: the
# pylons. Destructible pylon Area2Ds flank the core; each one projects a
# blue Line2D shield-beam to the core, and a semi-transparent blue shield
# bubble around the core visualises invulnerability.
#
# Killing a pylon:
#   - destroys its beam,
#   - drops the shield bubble + opens a 1.5s damage window on the core,
#   - escalates the boss's own fire cadence.
# After the disrupt window expires, if any pylon remains, the shield
# re-establishes.
#
# THE BOSS shoots — not the pylons. Phase cadence:
#   "both"      → fire_aimed_burst(3, 24°) every ~1.8s
#   "one_down"  → fire_aimed_burst(5, 22°) every ~1.2s
#   "core_only" → fire_aimed_burst(7, 28°) every 1.5s + 4-missile salvo every 3.5s
#
# Stats set BEFORE super._ready() — no fallback pattern.

const MissileScene = preload("res://scenes/projectiles/drifting_missile.tscn")
# Pylon is now a real scene (body art + orb + damage shader). Its root runs
# aegis_pylon.gd, so the hp/max_hp/side + pylon_killed contract is unchanged.
const PylonScene = preload("res://scenes/enemies/enemy_shield_pylon.tscn")

# Tuning knob (future sectors can override). Default 2 — keep parity with
# the existing fight. Pylons are placed evenly across [-pylon_offset_x,
# +pylon_offset_x]. Min 1 — at 1 the pylon centers on x=0 above the boss.
@export var num_pylons: int = 2
@export var pylon_hp: int = 80
@export var pylon_offset_x: float = 36.0

# Shield-disrupt window length when a pylon dies (sec).
@export var shield_disrupt_seconds: float = 1.5

# State: "both", "one_down", "core_only" — derived from live pylon count.
var _pylon_state: String = "both"
var _pylons: Array = []         # All live pylon Area2Ds.
var _pylon_beams: Dictionary = {}   # pylon -> Line2D
var _missile_t: float = 0.0
var _shield_disrupted_until: float = 0.0
var _shield_node: Sprite2D = null
var _shield_disrupt_flashing: bool = false


func _ready() -> void:
	max_health = 240
	bounty_value = 500
	display_scale = 1.0
	boss_hover_y = 56.0
	fire_interval_min = 1.5
	fire_interval_max = 1.5
	# Aimed sniper: precise cyan tracers fit the turret-core identity.
	# core_only phase overrides to burst_round per-call for the panic read.
	default_bullet_variant = load("res://data/bullets/boss/aimed_sniper.tres")
	# Empty phases — pylon-driven state machine handles the escalation.
	phases = []
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))
	_spawn_pylons()
	_spawn_shield_visual()


# ---- Pylon spawning ----------------------------------------------------

func _spawn_pylons() -> void:
	var n: int = max(1, num_pylons)
	for i in n:
		var local_x: float = 0.0
		if n > 1:
			var t: float = (float(i) / float(n - 1)) * 2.0 - 1.0
			local_x = t * pylon_offset_x
		var side_name: String = "p%d" % i
		var pylon := _make_pylon(local_x, side_name)
		add_child(pylon)
		_pylons.append(pylon)
		_spawn_beam_for(pylon)
	_update_pylon_state()


func _make_pylon(local_x: float, side_name: String) -> Area2D:
	# Instance the pylon scene (body + orb + collision + damage shader) instead
	# of building it inline. The scene root is an aegis_pylon Area2D, so the
	# hp/max_hp/side fields and pylon_killed signal we wire below are the same
	# contract this boss has always used.
	var pylon := PylonScene.instantiate() as Area2D
	pylon.name = "Pylon_" + side_name
	pylon.position = Vector2(local_x, 0)
	pylon.add_to_group("enemies")
	pylon.hp = pylon_hp
	pylon.max_hp = pylon_hp
	pylon.side = side_name
	pylon.pylon_killed.connect(_on_pylon_killed)
	return pylon


# ---- Beam visual (pylon -> boss core) ----------------------------------

func _spawn_beam_for(pylon: Area2D) -> void:
	# Line2D is parented to the boss so it inherits boss transform. Endpoints
	# are stored as the boss-local positions of the pylon + the boss core.
	var line := Line2D.new()
	line.name = "Beam_" + pylon.name
	line.width = 2.0
	line.default_color = Color(0.3, 0.7, 1.0, 0.85)
	line.z_index = -1  # Underneath the boss sprite.
	line.points = [pylon.position, Vector2.ZERO]
	add_child(line)
	_pylon_beams[pylon] = line


func _update_beams(time_s: float) -> void:
	# Pulse alpha sin(time), update endpoints (pylon may shift if boss is
	# scaled — points are boss-local so this is just a safety refresh).
	var pulse: float = 0.6 + 0.25 * (0.5 + 0.5 * sin(time_s * 4.0))
	var to_remove: Array = []
	for pylon in _pylon_beams.keys():
		var line: Line2D = _pylon_beams[pylon]
		if not is_instance_valid(pylon) or not is_instance_valid(line):
			to_remove.append(pylon)
			continue
		line.default_color = Color(0.3, 0.7, 1.0, pulse)
		line.points = [pylon.position, Vector2.ZERO]
	for k in to_remove:
		_pylon_beams.erase(k)


# ---- Shield bubble visual ----------------------------------------------

func _spawn_shield_visual() -> void:
	# Procedural circular gradient texture — radial blue, fading to alpha 0.
	const SIZE: int = 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (SIZE * 0.5)
			d = clamp(d, 0.0, 1.0)
			# Soft inner core, brighter ring at d≈0.85, fade to 0 at 1.0.
			var ring: float = exp(-pow((d - 0.85) * 6.0, 2.0))
			var inner: float = (1.0 - d) * 0.25
			var a: float = clamp(inner + ring * 0.55, 0.0, 0.75) * (1.0 - smoothstep(0.95, 1.0, d))
			img.set_pixel(x, y, Color(0.4, 0.75, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_shield_node = Sprite2D.new()
	_shield_node.texture = tex
	_shield_node.name = "ShieldBubble"
	_shield_node.z_index = 1  # Above sprite but cosmetic — no collision.
	# Scale so the bubble is ~1.5× the boss collision box (40×38).
	_shield_node.scale = Vector2(1.05, 1.05)
	_shield_node.modulate = Color(0.4, 0.75, 1.0, 1.0)
	add_child(_shield_node)


func _update_shield_visual(time_s: float) -> void:
	if _shield_node == null or not is_instance_valid(_shield_node):
		return
	if _pylon_state == "core_only":
		# Pylons all gone permanently — hide for good.
		_shield_node.visible = false
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _shield_disrupted_until:
		# Disrupt window — shield down, no pulse.
		_shield_node.visible = false
		return
	if not _shield_node.visible:
		_shield_node.visible = true
	# Pulse modulate alpha sin(time) — synchronised with beams.
	var pulse: float = 0.6 + 0.25 * (0.5 + 0.5 * sin(time_s * 4.0))
	_shield_node.modulate = Color(0.4, 0.75, 1.0, pulse)


# ---- Per-frame -----------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if _dying:
		return
	var time_s: float = Time.get_ticks_msec() / 1000.0
	_update_beams(time_s)
	_update_shield_visual(time_s)


# ---- Pylon death / state transitions -----------------------------------

func _on_pylon_killed(_side: String) -> void:
	# Remove its beam immediately.
	var to_remove: Array = []
	for pylon in _pylon_beams.keys():
		if not is_instance_valid(pylon):
			to_remove.append(pylon)
	for k in to_remove:
		var line = _pylon_beams[k]
		if is_instance_valid(line):
			line.queue_free()
		_pylon_beams.erase(k)
	# Drop dead pylons from the live list.
	var live: Array = []
	for p in _pylons:
		if is_instance_valid(p):
			live.append(p)
	_pylons = live
	# Open the disrupt window. If this was the last pylon, the shield
	# never re-establishes (core_only).
	_shield_disrupted_until = Time.get_ticks_msec() / 1000.0 + shield_disrupt_seconds
	_flash_shield_red()
	_update_pylon_state()
	_enrage_flash(Color(0.6, 1.0, 1.0, 1.0), 0.4)
	_screen_shake(4.0, 0.3)


func _flash_shield_red() -> void:
	# Brief red flash on the shield bubble (0.15s) just before it drops.
	if _shield_node == null or not is_instance_valid(_shield_node):
		return
	if _shield_disrupt_flashing:
		return
	_shield_disrupt_flashing = true
	var tw := _shield_node.create_tween()
	tw.tween_property(_shield_node, "modulate", Color(1.0, 0.25, 0.25, 0.9), 0.05)
	tw.tween_callback(func() -> void:
		_shield_disrupt_flashing = false
	)


func _update_pylon_state() -> void:
	var count: int = _pylons.size()
	if count >= 2:
		_pylon_state = "both"
	elif count == 1:
		_pylon_state = "one_down"
	else:
		_pylon_state = "core_only"


# ---- Damage gate: shield is up if any pylon alive AND not in window ----

func take_hit(damage: int = 1) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var shield_down: bool = _pylons.is_empty() or now < _shield_disrupted_until
	if not shield_down:
		# Visual feedback: hit-flash on the sprite + shield SFX.
		if has_node("Sprite2D"):
			var spr := $Sprite2D as Sprite2D
			var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
			HitFlashFx.flash(spr, HitFlashFx.FLASH_SHIELD)
		var ShieldSfx = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfx:
			ShieldSfx.play_hit(get_tree().root, global_position)
		return false
	return super.take_hit(damage)


# ---- Attack loop — BOSS shoots in every phase ---------------------------

func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		match _pylon_state:
			"both":
				await _paced(1.8).timeout
				if _dying:
					return
				fire_aimed_burst(3, 24.0)
			"one_down":
				await _paced(1.2).timeout
				if _dying:
					return
				fire_aimed_burst(5, 22.0)
			"core_only":
				await _paced(1.5).timeout
				if _dying:
					return
				# Burst round: red short-life streaks escalate the panic read
				# now that the shield pylons are gone and the core is exposed.
				fire_aimed_burst(7, 28.0, 0.0, load("res://data/bullets/boss/burst_round.tres"))
				_missile_t += 1.5
				if _missile_t >= 3.5:
					_missile_t = 0.0
					_drop_missile_salvo()


func _drop_missile_salvo() -> void:
	const SALVO: int = 4
	for i in SALVO:
		var m = MissileScene.instantiate()
		get_parent().add_child(m)
		var t: float = 0.0
		if SALVO > 1:
			t = (float(i) / float(SALVO - 1)) * 2.0 - 1.0
		var spawn_pos: Vector2 = global_position + Vector2(t * 40.0, 40.0)
		if m.has_method("start"):
			m.start(spawn_pos)
		else:
			m.global_position = spawn_pos
	# One launch report per salvo from the universal missile pool.
	WeaponSfx.play(get_tree().root, global_position, "missile")


func _on_boss_death() -> void:
	for p in _pylons:
		if is_instance_valid(p):
			p.queue_free()
	_pylons.clear()
	for line in _pylon_beams.values():
		if is_instance_valid(line):
			line.queue_free()
	_pylon_beams.clear()
	if _shield_node != null and is_instance_valid(_shield_node):
		_shield_node.queue_free()
