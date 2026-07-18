extends Node2D

# WEAPON STATUS widget (scenes/hud/hud_weapon_status.tscn) — self-contained
# port of ui.gd's armament rows (2026-07-14). Drop the scene into any HUD
# layer: it finds the player via the "player" group on its own and rebinds
# after respawn, so it can be moved/rearranged freely with no extra wiring.
#
# Row contract with the scene (each row: weapon_key / weapon_light /
# weapon_label / weapon_ammo):
#   Blaster   — label forced to "BLASTER"; the ammo slot shows the status text
#               (READY / FIRING / STANDBY) since the blaster is infinite.
#   Primary   — equipped PRIMARY cannon name + ammo count. The light carries
#               the ammo-state tell (dark = empty, flashing = regenerating).
#   Secondary — wing hardpoint name + ammo, or the Combat Drones deploy
#               countdown while one is live.
#   Super     — device-bay super name + charge tally ("|" per charge).

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Weapon-light ammo state animation (Roman 2026-06-10): flash while
# regenerating, darken when empty.
const WLIGHT_FLASH_HZ: float = 3.0

@onready var _blaster_light: Sprite2D = $Blaster/weapon_light
@onready var _blaster_status: Label = $Blaster/weapon_ammo
@onready var _pri_light: Sprite2D = $Primary/weapon_light
@onready var _pri_name: Label = $Primary/weapon_label
@onready var _pri_ammo: Label = $Primary/weapon_ammo
@onready var _sec_light: Sprite2D = $Secondary/weapon_light
@onready var _sec_name: Label = $Secondary/weapon_label
@onready var _sec_ammo_lbl: Label = $Secondary/weapon_ammo
@onready var _sup_light: Sprite2D = $Super/weapon_light
@onready var _sup_name: Label = $Super/weapon_label
@onready var _sup_ammo_lbl: Label = $Super/weapon_ammo

var _player_ref: Node = null
var _wlight_t: float = 0.0
var _sec_ammo: int = -1
# Combat Drones deploy timer: while a wave is live the secondary ammo slot
# shows a remaining-time countdown instead of the ammo count. _sec_timer_active
# gates _on_secondary_ammo_changed so the ammo signal can't clobber the timer.
var _sec_timer_active: bool = false
var _super_charges: int = 0


func _ready() -> void:
	$Blaster/weapon_label.text = "BLASTER"
	# Key hints render the live InputMap binding (bindings drift + are
	# user-rebindable).
	$Blaster/weapon_key.text = "[%s]" % _action_key_label("shoot")
	$Primary/weapon_key.text = "[%s]" % _action_key_label("shoot")
	$Secondary/weapon_key.text = "[%s]" % _action_key_label("shoot2")
	$Super/weapon_key.text = "[%s]" % _action_key_label("shoot_nose")
	_pri_ammo.text = ""
	_sec_ammo_lbl.text = ""
	_sup_ammo_lbl.text = ""


func bind_player(player: Node) -> void:
	_player_ref = player
	if player == null:
		return
	if player.has_signal("ammo_changed") and not player.ammo_changed.is_connected(_on_ammo_changed):
		player.ammo_changed.connect(_on_ammo_changed)
	if player.has_signal("secondary_ammo_changed") and not player.secondary_ammo_changed.is_connected(_on_secondary_ammo_changed):
		player.secondary_ammo_changed.connect(_on_secondary_ammo_changed)
	if player.has_signal("secondary_timer_changed") and not player.secondary_timer_changed.is_connected(_on_secondary_timer_changed):
		player.secondary_timer_changed.connect(_on_secondary_timer_changed)
	if player.has_signal("super_charges_changed") and not player.super_charges_changed.is_connected(_on_super_charges_changed):
		player.super_charges_changed.connect(_on_super_charges_changed)
	# Seed from current values
	if "ammo" in player:
		_on_ammo_changed(int(player.ammo))
	if "super_charges" in player and "max_super_charges" in player:
		_on_super_charges_changed(int(player.super_charges), int(player.max_super_charges))
	_refresh_weapon_names()


func _refresh_weapon_names() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# PRI row: the equipped PRIMARY gun (cannon_pool[1]) — the swap target,
	# shown whether or not it's currently the firing weapon (two-slot model).
	if _pri_name:
		var primary = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
		if primary != null and "display_name" in primary:
			_pri_name.text = String(primary.display_name)
		else:
			_pri_name.text = "—"
	if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
		var p_sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
		if _sec_name:
			if p_sec != null and "display_name" in p_sec:
				_sec_name.text = String(p_sec.display_name)
			else:
				_sec_name.text = "—"
		var p_sup = run.loadout_snapshot.get(Slots.SlotType.DEVICE_BAY_1, null)
		if _sup_name:
			if p_sup != null and "display_name" in p_sup:
				_sup_name.text = String(p_sup.display_name)
			else:
				_sup_name.text = "—"


func _on_ammo_changed(value: int) -> void:
	if _pri_ammo == null:
		return
	# Always show the count, incl. 0. -1 = infinite → "INF" (Roman 2026-07-15;
	# the pixel font has no ∞ glyph, it renders as a missing-char box).
	_pri_ammo.text = "INF" if value < 0 else "%d" % value
	_refresh_weapon_names()


func _on_secondary_ammo_changed(value: int, _maximum: int) -> void:
	_sec_ammo = value
	# While a Combat Drones deploy is live the slot shows the countdown timer;
	# don't let the ammo signal overwrite it. The ammo count re-renders when
	# the timer ends (_on_secondary_timer_changed active=false).
	if _sec_timer_active:
		return
	if _sec_ammo_lbl:
		_sec_ammo_lbl.text = "INF" if value < 0 else "%d" % value


# Combat Drones deploy timer. While active, the secondary ammo slot shows the
# remaining time (rounded-up seconds) instead of the ammo count. On expiry
# (active=false) the slot reverts to the cached deploy-ammo count.
func _on_secondary_timer_changed(seconds: float, active: bool) -> void:
	_sec_timer_active = active
	if _sec_ammo_lbl == null:
		return
	if active:
		_sec_ammo_lbl.text = "%ds" % int(ceil(seconds))
	else:
		_sec_ammo_lbl.text = "INF" if _sec_ammo < 0 else "%d" % _sec_ammo


func _on_super_charges_changed(value: int, _maximum: int) -> void:
	_super_charges = value
	if _sup_ammo_lbl:
		_sup_ammo_lbl.text = "|".repeat(value) if value > 0 else ""


func _action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = (ev as InputEventKey).physical_keycode
			if kc == 0:
				kc = (ev as InputEventKey).keycode
			if kc == 0:
				continue
			return OS.get_keycode_string(kc)
	return ""


func _process(delta: float) -> void:
	# Self-(re)bind: main.gd rebuilds the player node on respawn, so poll for a
	# live one instead of requiring external wiring.
	if _player_ref == null or not is_instance_valid(_player_ref):
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			bind_player(p)

	var run = get_node_or_null("/root/Run")
	if run != null:
		# "blaster" light = the active primary is an infinite blaster; "pri"
		# light = a metered cannon is active (single-active model 2026-06-11).
		var blaster_active: bool = run.is_active_cannon_infinite()

		if _blaster_light:
			_blaster_light.frame = 1 if blaster_active else 0
		if _blaster_status:
			_blaster_status.text = "STANDBY" if not blaster_active else ("FIRING" if Input.is_action_pressed("shoot") else "READY")

		if _pri_light:
			_pri_light.frame = 0 if blaster_active else 1
			# Ammo-state tell on the active replacement primary:
			#   no ammo      → darkened
			#   regenerating → flashing (below max + has a recharge rate)
			#   otherwise    → steady
			var lit := Color(1, 1, 1, 1)
			if not blaster_active and _player_ref != null and is_instance_valid(_player_ref):
				var p_ammo: int = int(_player_ref.ammo) if "ammo" in _player_ref else -1
				var p_max: int = int(_player_ref.ammo_max) if "ammo_max" in _player_ref else 0
				var p_rech: float = float(_player_ref.ammo_recharge_rate) if "ammo_recharge_rate" in _player_ref else 0.0
				if p_ammo == 0:
					lit = Color(1, 1, 1, 0.22)              # darkened — out of ammo
				elif p_ammo > 0 and p_ammo < p_max and p_rech > 0.0:
					_wlight_t += delta
					var a: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_wlight_t * WLIGHT_FLASH_HZ * TAU))
					lit = Color(1, 1, 1, a)                 # flashing — regenerating
			_pri_light.self_modulate = lit

		var sec_ok: bool = false
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			var sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
			sec_ok = sec != null and (_sec_ammo > 0 if _sec_ammo >= 0 else false)
		if _sec_light:
			_sec_light.frame = 1 if sec_ok else 0

		if _sup_light:
			_sup_light.frame = 1 if _super_charges > 0 else 0
