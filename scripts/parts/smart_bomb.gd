extends "res://scripts/parts/super_part.gd"

# Smart Bomb — DoDonPachi / Raiden classic panic super. On activation, in rapid
# sequence:
#   1. Flash the player white.
#   2. Release an expanding shockwave from the player travelling at the 8 px/f
#      clarity ceiling (480 px/s).
#   3. The shockwave grows until it is entirely off-screen, then frees itself.
# The shockwave (scripts/projectiles/smart_bomb_shockwave.gd) does the work:
# it IGNORES SHIELDS and one-shots any large non-tough enemy or smaller as its
# edge sweeps over them, cancels enemy bullets inside its radius, and bites
# bosses through the normal path. Tough / huge / bosses survive on HP.

const ShockwaveScript = preload("res://scripts/projectiles/smart_bomb_shockwave.gd")
const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")
const _DETONATE_CLIPS := [
	preload("res://assets/audio/weapons/player/smart_bomb_sweetener_1.ogg"),
	preload("res://assets/audio/weapons/player/smart_bomb_sweetener_2.ogg"),
]

# Tuned so Mk.1 (18) one-shots a large non-tough enemy (16 HP) and everything
# smaller; per-Mk growth lets late Marks bite tough/huge harder without ever
# one-shotting a boss.
@export var base_damage: int = 18
@export var dmg_per_mark: int = 5


func _init() -> void:
	super._init()
	display_name = "Super Pulse Bomb"
	description = "Releases a shockwave that ignores shields and clears large non-tough enemies. Limited charges, refill at outposts."
	# Stats live in resources/weapons/smart_bomb.tres (single source of truth).


func activate(ship) -> void:
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	# Invuln for the FULL on-screen lifetime of the shockwave (Roman 2026-06-08): the player
	# stays invincible while the wave is sweeping, not just a brief 0.6s. Also lets the
	# Touhou death-bomb hook in player.take_damage save the player from a fatal hit (that
	# path checks _invuln_t > 0 after fire_super to grant survival).
	if "_invuln_t" in ship:
		var wave_dur: float = ShockwaveScript.MAX_RADIUS / ShockwaveScript.SPEED
		ship._invuln_t = max(ship._invuln_t, wave_dur + 0.1)
	# 1. Flash the player white.
	if ship.has_node("Ship"):
		HitFlashFx.flash(ship.get_node("Ship"), HitFlashFx.FLASH_WHITE, 0.14)
	# 2. Release the shockwave from the player. Deferred add so it's safe even
	#    when fired from the death-bomb during a physics callback.
	var damage: int = _damage_at_mark(int(mark))
	var wave := ShockwaveScript.new()
	wave.configure(damage, ship.global_position)
	# Spawn into the ship's bullet_parent if it has one (the Hangar routes bullets
	# into its SubViewport world so they share the dummy's space) — else tree.root
	# per convention. Without this the shockwave lands in the main viewport at the
	# player's 480-coords => top-left of the screen in the bench.
	var wave_parent: Node = tree.root
	if "bullet_parent" in ship and ship.bullet_parent != null:
		wave_parent = ship.bullet_parent
	wave_parent.call_deferred("add_child", wave)
	# Punch.
	_camera_trauma(ship, 0.7)
	# Bomb detonation SFX — dedicated smart-bomb sweetener (Roman 2026-06-09).
	var clip: AudioStream = _DETONATE_CLIPS[randi() % _DETONATE_CLIPS.size()]
	Sfx.play_one_shot(clip, ship.global_position, -2.0)


func _damage_at_mark(at_mark: int) -> int:
	return base_damage + (at_mark - 1) * dmg_per_mark


func effective_damage(at_mark: int) -> int:
	return _damage_at_mark(at_mark)
