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
# Spread fire knobs — used by the Spread Cannon Part. Default 1 bullet
# straight forward (legacy behavior). Spread Cannon's apply() sets
# bullet_spread_count > 1 + bullet_spread_degrees > 0.
var bullet_spread_count: int = 1
var bullet_spread_degrees: float = 0.0
# Secondary fire pipeline — HARDPOINT_WING Part assigns these on apply()
# (Seeking Missile, Rocket Pod, future Side Pods / Drone Bits). Separate
# from the primary cannon's bullet_scene / cooldown / damage so the two
# fire independently. secondary_t counts up each frame; when it crosses
# secondary_cooldown the next fire_secondary press emits a bullet.
var secondary_bullet_scene: PackedScene = null
var secondary_cooldown: float = 0.5
var secondary_damage: int = 1
var secondary_homing: bool = false  # true for seeking missile
var _secondary_t: float = 0.0
# Continuous-beam secondary (Particle Beam). When non-empty, secondary
# fire ignores the bullet pipeline and instead runs a held-beam tick.
# Set to "beam" by ParticleBeam.apply(); empty string = bullet mode.
var secondary_mode: String = ""
# DPS-based beam damage — secondary_beam_dps × delta per frame, applied
# to every enemy in the column. Frame-rate independent; flat per-Mk
# (Mk grows the width, not the damage).
var secondary_beam_dps: float = 30.0
# Beam width — Particle Beam Part sets this; Mk scales it +1 px / Mk.
# Drives the visual width AND the hit-column tolerance so wider beam
# = larger hit area.
var secondary_beam_width: float = 6.0
# Three-layer beam visual:
#   _beam_halo — wide, low-alpha teal — bloom feel.
#   _beam_line — main beam, full-alpha teal.
#   _beam_core — narrow, white — hot core.
var _beam_halo: Line2D = null
var _beam_line: Line2D = null
var _beam_core: Line2D = null
var _beam_active: bool = false
# Super weapon slot — DEVICE_BAY_1 Part assigns itself here on apply().
# Charges are consumed on tap (single-use per press); refilled at
# outposts. Initial charges populated when the part is equipped.
var super_part: Resource = null
var super_charges: int = 0
var max_super_charges: int = 3
signal super_charges_changed(value: int, maximum: int)
# Hyper Mode timer — when > 0, fire_primary triggers every frame
# regardless of GunCooldown, and damage is multiplied. Driven by the
# Hyper super weapon's activate(); ticks down in _process.
var _hyper_t: float = 0.0
const HYPER_DAMAGE_MULT := 2.0
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
# Focus-mode slowdown — held `focus` action drops the ship to FOCUS_FACTOR
# of normal speed for precision dodging. Cave / Touhou convention; ~2/3.
const FOCUS_FACTOR := 0.55
var _focus_dot: Node2D = null

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
	position = Vector2(Playfield.CENTER.x, screensize.y - 30)
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
	# Restore super_charges from Run (persisted across scenes) — parts'
	# apply() already set max during _ready, so we just overwrite the
	# current charge count with whatever was saved. Run.super_charges
	# starts at 0 on new_run, but the part's initial apply has already
	# populated max_super_charges and run.super_charges (via the part).
	# Use the larger of the two on first combat so we start with full
	# charges.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "super_charges" in run and "max_super_charges" in run:
			if int(run.super_charges) <= 0 and run.super_charges < max_super_charges:
				# Fresh run — keep the full charges the part assigned and
				# sync Run so the snapshot starts off correct.
				run.super_charges = super_charges
				run.max_super_charges = max_super_charges
			else:
				# Returning from a meta scene with partial charges spent.
				super_charges = clampi(int(run.super_charges), 0, max_super_charges)
				super_charges_changed.emit(super_charges, max_super_charges)
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
	# Secondary cooldown ticks every frame regardless of input — so the
	# weapon recharges in the background and a tap fires immediately
	# whenever it's ready.
	_secondary_t = min(_secondary_t + delta, secondary_cooldown)
	if _hyper_t > 0.0:
		_hyper_t = max(0.0, _hyper_t - delta)
		# While hyper is active, bypass GunCooldown so primary fires every
		# frame. Damage gets scaled inside fire_primary below.
		can_shoot = true
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
	# Focus mode (Shift, by convention): ⅔-ish speed for precision
	# dodging + show the hitbox dot so the player sees their collider.
	var focused: bool = Input.is_action_pressed("focus")
	var focus_mult: float = FOCUS_FACTOR if focused else 1.0
	_update_focus_dot(focused)
	# Thrusters / Armor Plating upgrades feed into speed_multiplier;
	# applied here so the runtime stat reflects the live upgrade state.
	position += input * speed * speed_multiplier * focus_mult * delta
	position = Playfield.clamp_pos(position, 8.0)
	# Autofire toggle (Settings.autofire) latches primary fire on so
	# players don't have to hold the button. Holding still works
	# explicitly when autofire is off.
	var fire_held: bool = Input.is_action_pressed("shoot")
	if not fire_held and has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if "autofire" in s and s.autofire:
			fire_held = true
	if fire_held:
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
	# Secondary fire (C by default, hold-fire). Beam mode is held-tick
	# per-frame; bullet mode spawns a projectile per cooldown window.
	if secondary_mode == "beam":
		var holding: bool = Input.is_action_pressed("shoot2")
		_tick_beam(holding, delta)
	elif Input.is_action_pressed("shoot2"):
		fire_secondary()
	# Super weapon (X by default, single-tap, consumes a charge). Stub
	# until DEVICE_BAY slot Parts implement themselves.
	if Input.is_action_just_pressed("shoot_nose"):
		fire_super()

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
	# Touhou death-bomb hook — if this hit would be lethal AND the player
	# has a super charge available, auto-trigger the super instead. Costs
	# the charge but the super's invuln + cleanup keeps the player alive.
	# The activation itself sets _invuln_t so the bullet that triggered
	# this gets a free window.
	if hull - effective <= 0 and super_charges > 0 and super_part != null:
		fire_super()
		# Re-check — super activation should have set invuln; if not,
		# we fall through to taking the hit normally.
		if _invuln_t > 0.0:
			return
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
	# Spread support — Spread Cannon Part sets bullet_spread_count > 1.
	# Default 1 fires straight up exactly as before. For N > 1, fan the
	# bullets out across bullet_spread_degrees, centred straight up.
	var count: int = max(1, bullet_spread_count)
	var spread_rad: float = deg_to_rad(bullet_spread_degrees)
	for i in range(count):
		var angle: float = 0.0
		if count > 1:
			var t: float = float(i) / float(count - 1)
			angle = -spread_rad * 0.5 + spread_rad * t
		# 0 angle = straight up. (sin(a), -cos(a)) rotates around the up axis.
		var dir := Vector2(sin(angle), -cos(angle))
		var b: Node = bullet_scene.instantiate()
		get_tree().root.add_child(b)
		# Propagate the equipped cannon's damage to the bullet so per-Part /
		# per-Mark scaling actually reaches the take_hit call.
		# Hyper Mode doubles damage for its duration.
		if "damage" in b:
			var dmg: int = bullet_damage
			if _hyper_t > 0.0:
				dmg = int(round(float(bullet_damage) * HYPER_DAMAGE_MULT))
			b.damage = dmg
		b.start(position + Vector2(0, -8), dir)
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
	# HARDPOINT_WING Parts (Seeking Missile, Rocket Pod, future Side Pods)
	# write to secondary_bullet_scene / secondary_cooldown / secondary_damage
	# in their apply(). We spawn one bullet per cooldown window.
	if secondary_bullet_scene == null:
		return
	if not is_alive:
		return
	if _secondary_t < secondary_cooldown:
		return
	_secondary_t = 0.0
	var b: Node = secondary_bullet_scene.instantiate()
	get_tree().root.add_child(b)
	if "damage" in b:
		b.damage = secondary_damage
	if secondary_homing and "guided" in b:
		b.guided = true
	# Side-mounted hardpoints — spawn offset from the player so the
	# muzzle reads on a wingtip rather than the cannon nozzle. Direction
	# straight up (matches base_bullet default for player projectiles).
	b.start(position + Vector2(0, -10))


## Continuous Particle Beam ##

# Build the Line2D lazily on first beam tick. Stored as a child of the
# player so it inherits transforms — beam endpoints are in LOCAL coords
# (player origin = 0,0; muzzle slightly above).
func _ensure_beam_visual() -> void:
	if _beam_line and is_instance_valid(_beam_line):
		return
	# Halo — wide, low-alpha teal "glow." Drawn first so the main beam
	# overlays it. Width is sized in _tick_beam based on current beam_width.
	var halo := Line2D.new()
	halo.name = "ParticleBeamHalo"
	halo.default_color = Color(0.35, 0.85, 1.0, 0.35)
	halo.begin_cap_mode = Line2D.LINE_CAP_ROUND
	halo.end_cap_mode = Line2D.LINE_CAP_ROUND
	halo.z_index = 4
	halo.visible = false
	# Main beam — teal/cyan, full alpha.
	var line := Line2D.new()
	line.name = "ParticleBeam"
	line.default_color = Color(0.55, 0.95, 1.0, 1.0)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5
	line.visible = false
	# Core — narrow, white hot center.
	var core := Line2D.new()
	core.name = "ParticleBeamCore"
	core.default_color = Color(1.0, 1.0, 1.0, 1.0)
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	core.z_index = 6
	core.visible = false
	# Deferred adds avoid "parent busy" during the first tick after equip.
	if is_inside_tree():
		add_child.call_deferred(halo)
		add_child.call_deferred(line)
		add_child.call_deferred(core)
	else:
		add_child(halo)
		add_child(line)
		add_child(core)
	_beam_halo = halo
	_beam_line = line
	_beam_core = core


# Per-frame: scan enemies in a vertical column above the player, sorted
# by Y descending so we hit the nearest first. Pierce through any enemy
# that ISN'T flagged tough/boss; stop on the first tough/boss enemy.
# Damage applied = secondary_beam_dps × delta to every enemy in the path.
const TOUGH_HP_THRESHOLD := 8  # enemies with > 8 max_hull count as "tough"


func _tick_beam(holding: bool, delta: float) -> void:
	_ensure_beam_visual()
	if not holding or not is_alive:
		if _beam_active:
			_beam_active = false
			if _beam_halo: _beam_halo.visible = false
			if _beam_line: _beam_line.visible = false
			if _beam_core: _beam_core.visible = false
		return
	_beam_active = true
	if _beam_halo: _beam_halo.visible = true
	if _beam_line: _beam_line.visible = true
	if _beam_core: _beam_core.visible = true
	# Width drives the visual AND the hit-column tolerance. Halo bloats
	# 60% wider than main; core is 35% as wide for a hot center.
	if _beam_line:
		_beam_line.width = secondary_beam_width
	if _beam_halo:
		_beam_halo.width = secondary_beam_width * 1.6
	if _beam_core:
		_beam_core.width = max(1.0, secondary_beam_width * 0.35)
	var beam_half_width: float = secondary_beam_width * 0.5 + 2.0
	# Find the first tough/boss enemy in the beam's column; that's where
	# the beam stops. Soft enemies between us and it get damaged.
	var tree := get_tree()
	if tree == null:
		return
	var enemies_in_column: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip enemies BELOW the player or outside the beam's x band.
		if e.global_position.y > global_position.y:
			continue
		if abs(e.global_position.x - global_position.x) > beam_half_width:
			continue
		enemies_in_column.append(e)
	enemies_in_column.sort_custom(_sort_by_y_desc)
	# DPS × delta — frame-rate independent. At 60 fps + 30 DPS that
	# rounds to 1 dmg/tick (since int(round(0.5)) = 1 on tied rounding,
	# but max(1, ...) guards anyway).
	var dmg_amount: int = max(1, int(round(secondary_beam_dps * delta)))
	var stop_y: float = -screensize.y  # default: top of world
	for e in enemies_in_column:
		if e.has_method("take_hit"):
			e.take_hit(dmg_amount)
		if _is_tough_or_boss(e):
			# Beam stops here — set end point at the enemy's Y, exit.
			stop_y = e.global_position.y - global_position.y
			break
	# All three layers share the same start/end points so they composite
	# as halo-under-beam-under-core. Muzzle just above the ship.
	var points := PackedVector2Array([
		Vector2(0, -10),
		Vector2(0, stop_y),
	])
	if _beam_halo: _beam_halo.points = points
	if _beam_line: _beam_line.points = points
	if _beam_core: _beam_core.points = points


func _sort_by_y_desc(a, b) -> bool:
	return a.global_position.y > b.global_position.y


# Tough/boss detection — scene_file_path string match catches the three
# named bosses; max_hull threshold catches "elite" chaff like bulwark,
# bomber, frigate, etc.
func _is_tough_or_boss(enemy: Node) -> bool:
	if enemy == null:
		return false
	var path: String = enemy.scene_file_path if "scene_file_path" in enemy else ""
	if path.find("boss") != -1:
		return true
	if "max_hull" in enemy and int(enemy.max_hull) > TOUGH_HP_THRESHOLD:
		return true
	if "max_health" in enemy and int(enemy.max_health) > TOUGH_HP_THRESHOLD:
		return true
	return false


func fire_super() -> void:
	# Single-tap super weapon. Needs an equipped DEVICE_BAY Part and at
	# least one charge. Part owns the activation effect (Smart Bomb /
	# Hyper / Drone Swarm / Phase Shift).
	if super_part == null:
		return
	if super_charges <= 0:
		return
	if not is_alive:
		return
	super_charges -= 1
	super_charges_changed.emit(super_charges, max_super_charges)
	# Persist immediately so a mid-combat scene swap (death, level clear)
	# carries the consumed charge forward.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "super_charges" in run:
			run.super_charges = super_charges
	if super_part.has_method("activate"):
		super_part.activate(self)


# Spawn a 4-px white dot at the ship's center so the player can see the
# exact hitbox while focus-dodging. Only visible when focus is held;
# matches Touhou's iconic centered hitbox indicator.
func _update_focus_dot(visible: bool) -> void:
	if _focus_dot == null:
		_focus_dot = Node2D.new()
		_focus_dot.name = "FocusDot"
		var dot := ColorRect.new()
		dot.size = Vector2(4, 4)
		dot.position = Vector2(-2, -2)
		dot.color = Color(1, 1, 1, 0.95)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_dot.add_child(dot)
		_focus_dot.z_index = 100
		add_child(_focus_dot)
	_focus_dot.visible = visible

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
