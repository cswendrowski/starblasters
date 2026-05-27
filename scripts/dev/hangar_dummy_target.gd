extends Area2D

# Hangar dummy target. Listens for bullet hits and plays a hit-flash so
# the player can verify cannon damage visually. Never dies; pretends to
# have infinite HP so the test session keeps running.
#
# DPS counter: tracks damage events in the last 5 seconds via a ring buffer
# of (time, damage) pairs. Displays "DPS: X.X" on a Label above the sprite.
# Resets to 0 naturally when no hits occur within the 5-second window.

const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")

const DPS_WINDOW := 5.0  # seconds

var _hit_log: Array = []  # Array of [time_sec: float, damage: int]
var _dps_label: Label = null


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_dps_label = Label.new()
	_dps_label.name = "DpsLabel"
	_dps_label.text = "DPS: 0.0"
	_dps_label.position = Vector2(-20, -22)
	_dps_label.size = Vector2(40, 8)
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dps_label.add_theme_font_size_override("font_size", 6)
	_dps_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	add_child(_dps_label)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var cutoff := now - DPS_WINDOW
	# Prune events older than the window.
	var i := 0
	while i < _hit_log.size():
		if float(_hit_log[i][0]) < cutoff:
			_hit_log.remove_at(i)
		else:
			i += 1
	# Sum damage in window.
	var total_dmg := 0
	for entry in _hit_log:
		total_dmg += int(entry[1])
	var dps := float(total_dmg) / DPS_WINDOW
	if _dps_label:
		_dps_label.text = "DPS: %.1f" % dps


func _on_area_entered(area: Area2D) -> void:
	# Bullets call take_hit on us through the BaseBullet pipeline; we
	# don't need to handle the impact here. The flash is for non-take_hit
	# code paths (impact sprites still spawn via the bullet itself).
	pass


# Bullet pipeline routes here for damage. We swallow it but play the flash
# so the player sees the bullet land. take_hit returns false (not fatal).
func take_hit(damage: int = 1) -> bool:
	if has_node("Sprite2D"):
		HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_WHITE)
	# Record hit for DPS calculation.
	var now := Time.get_ticks_msec() / 1000.0
	_hit_log.append([now, damage])
	return false


# Bulwark-shield path checks this. We're not shielded.
func has_meta_bulwark_shielded() -> bool:
	return false
