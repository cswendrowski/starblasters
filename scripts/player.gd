extends Area2D

signal shield_changed
signal hull_changed
signal died
# Emitted whenever take_damage() actually applies damage (before shield/hull
# absorption). Lets the HUD react to the magnitude of the hit without having
# to diff old vs new bar values.
signal damaged(amount: int)

# ---- Stats (mutated by equipped Parts) ----
# Base values; Parts add on top. Gives a sane floor even with no parts equipped.
var speed: float = 125.0  # 320×400 res — halved from 250
var cooldown: float = 0.15
var bullet_damage: int = 1
# Exported so player.tscn can assign a fallback bullet; parts override at runtime.
@export var bullet_scene: PackedScene
@export var super_scene: PackedScene
@export var heavy_scene: PackedScene
@export var chain_scene: PackedScene

# Pool of hit-flinch SFX rotated each time the player takes a hit. Two
# variants keep the sound from feeling samey under sustained fire.
const HIT_SFX_POOL: Array = [
	preload("res://Sound/SFX_hit&damage3.wav"),
	preload("res://Sound/SFX_hit&damage9.wav"),
]
var _hit_sfx_idx: int = 0

# Shield: a pool of CHARGES, not a damage soak. Each charge fully blocks
# one hit regardless of incoming damage and grants brief i-frames. One
# charge recharges every `shield_recharge_seconds` while the pool is below
# max. Roman, 2026-05-17 design pass.
var max_shield: int = 3
var shield: int = 3:
	set = set_shield
# Time per charge regen. Reduced by the Shield Recharge outpost upgrade.
var shield_recharge_seconds: float = 30.0
# I-frames in seconds after a shield absorbs a hit. Stops chained
# instant-kills (mine + bomblet) from one-shotting the player.
const SHIELD_INVULN_SECONDS: float = 0.6
var _invuln_t: float = 0.0

# Hull: does NOT regen automatically; death at 0. Outpost "Self Repair"
# heals N hull at combat start, "Hull" upgrade adds N to max.
var max_hull: int = 50
var hull: int = 50:
	set = set_hull
# Damage reduction applied to hull damage (Armor Plating upgrade).
var hull_damage_reduction: float = 0.0
# Speed multiplier from upgrades (Thrusters +, Armor Plating −). Applied
# in _process so the live speed = base * speed_multiplier.
var speed_multiplier: float = 1.0

var can_shoot: bool = true
var is_alive: bool = true
# Equipped CANNON style. "energy" (default Energy Blaster — blue muzzle,
# silent, infinite ammo) or "machinegun" (brrrt loop, smoke + shells,
# limited ammo). Set by the equipped CANNON Part.
var weapon_style: String = "energy"
# Per-cannon SFX tag — set by the equipped cannon's apply(). Routed to
# WeaponSfx.play() in fire_primary so each weapon has its own sound.
var fire_sfx_kind: String = "blaster_small"
# Ammo for the equipped CANNON. -1 means infinite (Energy Blaster). >= 0
# means counted (Machinegun). Outpost refills write here via Run.ammo.
var ammo: int = -1
signal ammo_changed(value: int)
# Set false during intro/outro cinematics — _process still runs (so external
# tweens of position work), but input is ignored.
var controls_enabled: bool = true
const PlayerLoadoutCls = preload("res://scripts/weapons/loadout.gd")
const PartFactoryCls = preload("res://scripts/parts/part_factory.gd")

var loadout

# ---- Sci-Fi Shield FX ----
# Code-only ring sprite (no .tscn edit). Sits as a child of Player so it
# follows the ship; bullets still spawn at root.
const SHIELD_SHADER = preload("res://graphics/sci_fi_shield.gdshader")
var _shield_ring: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_alpha_tween: Tween = null
var _shield_hit_tween: Tween = null

# Machinegun audio — loop while firing, end SFX on release.
var _mg_loop_player: AudioStreamPlayer2D = null
var _mg_end_player: AudioStreamPlayer2D = null
var _mg_firing: bool = false

@onready var screensize: Vector2 = get_viewport_rect().size

func _ready() -> void:
	# Self-register in the "player" group so enemies (smart bomblets,
	# homing mines) can find us via get_nodes_in_group("player"). Without
	# this, the smart cluster mines could never see a target.
	if not is_in_group("player"):
		add_to_group("player")
	loadout = PlayerLoadoutCls.new()
	loadout.name = "Loadout"
	add_child(loadout)
	PartFactoryCls.default_starting_loadout(loadout)
	# Apply any parts the player bought / picked up between scenes. Run
	# stores them in `loadout_snapshot[slot] = part`; we equip on top of
	# the default loadout so a purchased CANNON / SHIELD / etc actually
	# shows up in combat (Roman, 2026-05-17: "they weren't actually being
	# added to the player ship when bought" — loadout_snapshot was never
	# being read into combat).
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			for slot in run.loadout_snapshot.keys():
				var part = run.loadout_snapshot[slot]
				if part != null:
					loadout.equip(int(slot), part)
	_setup_shield_ring()
	_setup_mg_audio()
	_setup_smoke_trail()
	# Ground shadow on the top parallax layer (Roman, 2026-05-16: ships
	# cast a drop shadow on first-layer parallax objects).
	var ParallaxShadow = load("res://scripts/effects/parallax_shadow.gd")
	ParallaxShadow.attach(self)
	# Oblique drop-shadow under the ship sprite (code-only; no .tscn edits).
	var ShadowFx = load("res://scripts/shadow_fx.gd")
	ShadowFx.attach_shadow($Ship)
	# Engine glow under the booster animation so the thrust reads as a
	# light source. Cyan-blue to match the booster art.
	var GlowFx = load("res://scripts/effects/glow_fx.gd")
	if $Ship.has_node("Boosters"):
		var booster: Node2D = $Ship.get_node("Boosters") as Node2D
		var glow = GlowFx.attach_glow($Ship, Color(0.45, 0.85, 1.0), 1.2, 0.75)
		glow.position = booster.position
	start()

func _setup_smoke_trail() -> void:
	# Sprite-based smoke trail (DamageSmokeTrail spawns one Sprite2D per puff,
	# tweens it downward + fading). Simpler and more reliable than the
	# CPUParticles2D approach which silently failed to render.
	var TrailCls = preload("res://scripts/effects/damage_smoke_trail.gd")
	var trail = TrailCls.new()
	trail.name = "DamageSmokeTrail"
	add_child(trail)
	trail.set_player(self)
	# Procedural torch fire on the engine nozzle (Roman 2026-05-18). Reads
	# horizontal velocity each frame and pipes it into the shader's
	# windForce so the flame leans opposite the direction of travel.
	var EngineTorchCls = preload("res://scripts/effects/engine_torch.gd")
	EngineTorchCls.attach_to_player(self)


func _setup_mg_audio() -> void:
	# Two AudioStreamPlayer2D nodes: the loop runs while the trigger is held,
	# the end SFX punctuates the release.
	#
	# Roman, 2026-05-16: "apply a modest low-pass filter." Earlier attempt to
	# install a runtime "Weapons" bus with a LowPassFilter killed all audio in
	# the build — root cause never confirmed but the bus mutation was the only
	# suspect. To dodge that entirely, the filter is *pre-baked* into the OGG
	# (ffmpeg `lowpass=f=4000`). The `-LP.ogg` files are committed alongside
	# the originals. pitch_scale is dialed back closer to neutral now that the
	# muffle character comes from the filter instead of pitch.
	var loop_stream: AudioStream = load("res://Sound/weapons/Machinegun-Loop-LP.ogg")
	if loop_stream is AudioStreamOggVorbis:
		(loop_stream as AudioStreamOggVorbis).loop = true
	_mg_loop_player = AudioStreamPlayer2D.new()
	_mg_loop_player.name = "MgLoop"
	_mg_loop_player.stream = loop_stream
	_mg_loop_player.volume_db = -3.0
	_mg_loop_player.pitch_scale = 0.92
	add_child(_mg_loop_player)

	var end_stream: AudioStream = load("res://Sound/weapons/Machinegun-End-LP.ogg")
	_mg_end_player = AudioStreamPlayer2D.new()
	_mg_end_player.name = "MgEnd"
	_mg_end_player.stream = end_stream
	_mg_end_player.volume_db = -3.0
	_mg_end_player.pitch_scale = 0.92
	add_child(_mg_end_player)


func _setup_shield_ring() -> void:
	# ColorRect is a Control; size in local space. Player is scaled 3x by its
	# parent, so 26 local px = 78 screen px ring diameter (comfortably wraps the
	# 16x16 ship).
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.0)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)

	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1) # shader drives final color
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_ring.size = Vector2(26, 26)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)

func start() -> void:
	show()
	is_alive = true
	position = Vector2(screensize.x / 2, screensize.y - 64)
	# Run-level upgrades (outpost purchases) feed into max_hull, max_shield,
	# shield_recharge, hull_damage_reduction, and speed_multiplier here so
	# every combat scene picks up the latest upgrade state.
	apply_run_upgrades()
	shield = max_shield  # combat level starts fully-shielded per Roman 2026-05-17
	# Self Repair upgrade heals N hull at combat start. Cap at max so it
	# can't over-cap an already-healthy player.
	var self_repair: int = _self_repair_amount()
	hull = clampi(hull + self_repair, 0, max_hull) if hull > 0 else max_hull
	if hull == 0:
		hull = max_hull
	can_shoot = true
	$GunCooldown.wait_time = cooldown
	$ShieldRegenTimer.wait_time = max(0.5, shield_recharge_seconds)
	# Only start regen if a charge is actually missing. Roman, 2026-05-17:
	# "Shield recharge shouldn't start until a shield charge is expended."
	if shield < max_shield:
		$ShieldRegenTimer.start()
	else:
		$ShieldRegenTimer.stop()
	# Force-emit UI updates so bars reflect current loadout
	shield_changed.emit(max_shield, shield)
	hull_changed.emit(max_hull, hull)
	# Initial shield-ring visibility matches starting shield.
	_set_shield_ring_alpha(1.0 if shield > 0 else 0.0, 0.0)

func _process(delta: float) -> void:
	if not is_alive:
		return
	if _invuln_t > 0.0:
		_invuln_t = max(0.0, _invuln_t - delta)
	if not controls_enabled:
		# Ship still animates "forward" so it reads as actively flying during
		# the intro slide-in / outro fly-out cinematic.
		$Ship.frame = 1
		$Ship/Boosters.animation = "forward"
		# Stop any in-flight machinegun audio so the loop doesn't keep
		# brrrt'ing while the player is flying off-screen at level end
		# (Roman, 2026-05-16: "make sure to stop them shooting").
		if _mg_firing:
			_mg_firing = false
			if _mg_loop_player and _mg_loop_player.playing:
				_mg_loop_player.stop()
		return
	var input := Input.get_vector("left", "right", "up", "down")
	if input.x > 0:
		$Ship.frame = 2
		$Ship/Boosters.animation = "right"
	elif input.x < 0:
		$Ship.frame = 0
		$Ship/Boosters.animation = "left"
	else:
		$Ship.frame = 1
		$Ship/Boosters.animation = "forward"
	# Thrusters / Armor Plating upgrades feed into speed_multiplier;
	# applied here so the runtime stat reflects the live upgrade state.
	position += input * speed * speed_multiplier * delta
	position = position.clamp(Vector2(8, 8), screensize - Vector2(8, 8))
	if Input.is_action_pressed("shoot"):
		fire_primary()
		# MG audio loop only when the machinegun is the equipped CANNON
		# AND there's still ammo. Energy blaster fire is silent.
		if weapon_style == "machinegun" and ammo != 0 and not _mg_firing and is_alive:
			_mg_firing = true
			if _mg_loop_player and not _mg_loop_player.playing:
				_mg_loop_player.play()
	elif _mg_firing:
		_mg_firing = false
		if _mg_loop_player and _mg_loop_player.playing:
			_mg_loop_player.stop()
		if _mg_end_player and is_alive and weapon_style == "machinegun":
			_mg_end_player.play()
	if Input.is_action_pressed("shoot_nose"):
		fire_secondary()

# ---- Damage pipeline ----
# Shield is a charge pool: one charge fully absorbs one hit (regardless
# of damage amount) and grants i-frames. Once charges run out, damage
# bleeds straight into hull (no partial soak). Roman, 2026-05-17.
func take_damage(amount: int) -> void:
	if not is_alive or amount <= 0:
		return
	# I-frame window — comes after a shield absorb. Lets the player
	# break out of mine + bomblet pile-ons that would otherwise stack.
	if _invuln_t > 0.0:
		return
	# Sector damage scaling (Roman framework): +5% incoming damage per
	# sector beyond 1. Applies to all enemy damage sources (bullets,
	# contact, mines, asteroids) since they all funnel through here.
	# Shield charges are binary so this only meaningfully scales hull bleed.
	if has_node("/root/Run"):
		var s: int = int(get_node("/root/Run").sectors_cleared)
		if s > 0:
			amount = max(1, int(round(float(amount) * (1.0 + 0.05 * float(s)))))
	var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
	if shield > 0:
		# Charge consumed, regardless of damage amount.
		shield -= 1
		_invuln_t = SHIELD_INVULN_SECONDS
		damaged.emit(0)
		_pulse_shield_ring()
		if has_node("Ship"):
			HitFlashFx.flash($Ship, HitFlashFx.FLASH_SHIELD)
		return
	# No shield — apply armor-plated DR then bleed into hull.
	var effective: int = max(1, int(round(float(amount) * (1.0 - hull_damage_reduction))))
	damaged.emit(effective)
	hull -= effective
	if has_node("Ship"):
		HitFlashFx.flash($Ship, HitFlashFx.FLASH_WHITE)

func set_shield(value: int) -> void:
	var prev := shield
	shield = clampi(value, 0, max_shield)
	shield_changed.emit(max_shield, shield)
	# Roman, 2026-05-18: shield-hit / shield-break SFX. Only on DRAINS
	# (regen ticks back up silently). Break plays when the last charge
	# is consumed; otherwise it's a normal hit.
	if prev > shield:
		var ShieldSfx = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfx:
			if shield == 0:
				ShieldSfx.play_break(get_tree().root, global_position)
			else:
				ShieldSfx.play_hit(get_tree().root, global_position)
	# Regen timer ticks every `shield_recharge_seconds` while charges are
	# below max. The Shield Recharge upgrade shortens this; the upgrade
	# applier writes shield_recharge_seconds before combat starts.
	if shield < max_shield and has_node("ShieldRegenTimer"):
		$ShieldRegenTimer.wait_time = max(0.5, shield_recharge_seconds)
		if $ShieldRegenTimer.is_stopped():
			$ShieldRegenTimer.start()
	elif shield >= max_shield and has_node("ShieldRegenTimer"):
		# At cap — halt regen until the next hit drops us below max.
		$ShieldRegenTimer.stop()
	# FX gates — the shield ring is visible only while we have charges.
	if has_node("ImpactParticle"):
		$ImpactParticle.restart()
	if has_node("Ship/Shield/ShieldFlash"):
		$Ship/Shield/ShieldFlash.play()
	if prev > 0 and shield == 0:
		_set_shield_ring_alpha(0.0, 0.3)
	elif prev == 0 and shield > 0:
		_set_shield_ring_alpha(1.0, 0.25)

func set_hull(value: int) -> void:
	hull = clampi(value, 0, max_hull)
	hull_changed.emit(max_hull, hull)
	$ImpactParticle.restart()
	if hull <= 0:
		die()

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	hide()
	died.emit()
	$ShieldRegenTimer.stop()
	$GunCooldown.stop()
	can_shoot = false
	# Cut the MG loop the moment we die — otherwise the audio outlives the
	# player by half a second of "...brrrt".
	if _mg_loop_player and _mg_loop_player.playing:
		_mg_loop_player.stop()
	_mg_firing = false
	$Death.play()

# ---- Fire paths ----
# Primary fire is driven by the CANNON slot Part. Secondary fire will be
# driven by hardpoint/device parts (Phase 2+); for now it's a hook only.
func fire_primary() -> void:
	if not can_shoot or bullet_scene == null:
		return
	# Machinegun: out of ammo → silent click + abort. Energy blaster is
	# unmetered (ammo == -1).
	if weapon_style == "machinegun" and ammo == 0:
		return
	can_shoot = false
	$GunCooldown.start()
	var muzzle_pos: Vector2 = global_position + Vector2(0, -8)
	var b: Node = bullet_scene.instantiate()
	get_tree().root.add_child(b)
	# Propagate the equipped cannon's damage to the bullet so per-Part /
	# per-Mark scaling actually reaches the take_hit call. Pre-refactor
	# the bullet hardcoded damage=1 regardless of the part's bullet_damage.
	if "damage" in b:
		b.damage = bullet_damage
	b.start(position + Vector2(0, -8))
	# Style-specific muzzle FX + per-shot SFX.
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	if weapon_style == "machinegun":
		MuzzleFx.play(muzzle_pos)  # warm flash + smoke + shell
		if ammo > 0:
			ammo -= 1
			ammo_changed.emit(ammo)
			if has_node("/root/Run"):
				get_node("/root/Run").ammo = ammo
	else:
		MuzzleFx.play_energy(muzzle_pos)
		# Per-shot cannon SFX, dispatched by the equipped cannon's
		# fire_sfx_kind. Falls back to the legacy ShootSound when the
		# kind is empty (e.g., laser beam — sounds not yet supplied).
		var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
		if WeaponSfx and fire_sfx_kind != "":
			WeaponSfx.play(get_tree().root, global_position, fire_sfx_kind)
		elif has_node("ShootSound"):
			$ShootSound.play()
	var tween := create_tween().set_parallel(false)
	tween.tween_property($Ship, "position:y", 1, 0.1)
	tween.tween_property($Ship, "position:y", 0, 0.05)


# Ammo setter for the CANNON Part to plumb its starting ammo. Public so
# Outpost / Junk Trader refill paths can also call it directly.
func set_ammo(value: int) -> void:
	ammo = value
	ammo_changed.emit(ammo)
	if has_node("/root/Run"):
		get_node("/root/Run").ammo = ammo

func fire_secondary() -> void:
	# Hook for hardpoint weapons; no-op until a secondary Part is equipped.
	pass

func _on_gun_cooldown_timeout() -> void:
	can_shoot = true

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemies"):
		area.explode()
		_play_hit_sfx()
		take_damage(2)
	elif area.is_in_group("bullets"):
		_play_hit_sfx()
		take_damage(1)

func _play_hit_sfx() -> void:
	# Alternate between &damage3.wav and &damage9.wav so repeated hits don't
	# stack the exact same waveform.
	if not has_node("BulletHit"):
		return
	var p: AudioStreamPlayer2D = $BulletHit
	p.stream = HIT_SFX_POOL[_hit_sfx_idx]
	_hit_sfx_idx = (_hit_sfx_idx + 1) % HIT_SFX_POOL.size()
	p.pitch_scale = randf_range(0.96, 1.05)
	p.play()


func _on_shield_regen_timer_timeout() -> void:
	# One charge per tick. set_shield() restarts the timer when shield
	# is still below max, so the recharge continues automatically.
	if shield < max_shield:
		shield += 1


# Read upgrade Mks from /root/Run and translate them into runtime stats.
# Called from start() so every combat scene picks up the latest values.
#   Hull            +10 max hull per Mk
#   Armor Plating   +5% hull DR per Mk, -2% speed per Mk
#   Thrusters       +3% speed per Mk
#   Self Repair     heal 5+2*Mk hull at combat start (applied by start())
#   Shield Capacity +1 shield charge per Mk
#   Shield Recharge -2 sec recharge per Mk (floored at 4s minimum)
func apply_run_upgrades() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	max_hull = 50 + int(run.hull_mk) * 10
	hull_damage_reduction = clamp(float(run.armor_mk) * 0.05, 0.0, 0.85)
	var speed_pct: float = 1.0 + float(run.thrusters_mk) * 0.03 - float(run.armor_mk) * 0.02
	speed_multiplier = max(0.3, speed_pct)
	max_shield = 3 + int(run.shield_cap_mk)
	shield_recharge_seconds = max(4.0, 30.0 - float(run.shield_recharge_mk) * 2.0)


# Self Repair upgrade heal-on-combat-start amount.
func _self_repair_amount() -> int:
	if not has_node("/root/Run"):
		return 0
	var run = get_node("/root/Run")
	if int(run.self_repair_mk) <= 0:
		return 0
	return 5 + int(run.self_repair_mk) * 2


# ---- Shield ring helpers ----
func _set_shield_ring_alpha(target: float, duration: float) -> void:
	if _shield_mat == null:
		return
	if _shield_alpha_tween and _shield_alpha_tween.is_valid():
		_shield_alpha_tween.kill()
	if duration <= 0.0:
		_shield_mat.set_shader_parameter("alpha", target)
		return
	_shield_alpha_tween = create_tween()
	var current: float = float(_shield_mat.get_shader_parameter("alpha"))
	_shield_alpha_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("alpha", v),
		current, target, duration
	)

func _pulse_shield_ring() -> void:
	if _shield_mat == null:
		return
	if _shield_hit_tween and _shield_hit_tween.is_valid():
		_shield_hit_tween.kill()
	_shield_mat.set_shader_parameter("hit_strength", 1.0)
	_shield_hit_tween = create_tween()
	_shield_hit_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("hit_strength", v),
		1.0, 0.0, 0.35
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
