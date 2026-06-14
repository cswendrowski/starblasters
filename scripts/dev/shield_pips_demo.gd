extends Control

# Standalone demo of the shield pip strip. Builds a fake "player" stub
# that exposes the contract `shield_pips_hud.gd` needs (max_shield,
# shield, shield_recharge_seconds, ShieldRegenTimer child, shield_changed
# signal) and steps it through drain/recharge so the visual reads.
#
# Used by tools/capture_shield_gif.gd to generate a GIF for Roman.

const ShieldPipsCls = preload("res://scripts/hud/shield_pips_hud.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# Fake player — a Node with the property/signal surface the pip hud
# expects. We can't reuse the real player.gd because it imports the
# whole combat dependency tree.
class FakePlayer extends Node:
	signal shield_changed
	var max_shield: int = 3
	var shield: int = 3
	var shield_recharge_seconds: float = 2.0
	func emit_shield_changed():
		shield_changed.emit(max_shield, shield)


var _pips
var _player: FakePlayer = null
var _label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Dim space-ish backdrop so the pips read against something.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Fake player with a ShieldRegenTimer child the pip hud can read.
	_player = FakePlayer.new()
	_player.name = "FakePlayer"
	var timer := Timer.new()
	timer.name = "ShieldRegenTimer"
	timer.one_shot = true
	timer.wait_time = _player.shield_recharge_seconds
	_player.add_child(timer)
	add_child(_player)

	# Center the pip strip in the 320×400 canvas.
	_pips = ShieldPipsCls.new()
	_pips.name = "ShieldPips"
	_pips.position = Vector2(120, 180)
	_pips.size = Vector2(80, 16)
	# Scale up 3× so the GIF capture clearly shows the pips.
	_pips.scale = Vector2(3, 3)
	_pips.position = Vector2(40, 160)
	add_child(_pips)
	_pips.bind_player(_player)

	# Caption.
	_label = Label.new()
	_label.text = "SHIELD"
	_label.position = Vector2(20, 100)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	add_child(_label)

	# Step through a scripted shield sequence so the GIF demonstrates
	# every state: drain → recharge → full → drain again.
	_run_demo()


func _run_demo() -> void:
	await get_tree().create_timer(0.5).timeout
	# Drain three times in quick succession.
	for i in 3:
		_drain()
		await get_tree().create_timer(0.6).timeout
	# Recharge cycles.
	for i in 3:
		_recharge()
		await get_tree().create_timer(2.2).timeout
	# Final drain pair to show flash on full pips.
	_drain()
	await get_tree().create_timer(0.6).timeout
	_drain()


func _drain() -> void:
	if _player.shield <= 0:
		return
	_player.shield -= 1
	_player.emit_shield_changed()
	# Restart regen timer so the recharging-pip animation kicks in.
	var t: Timer = _player.get_node("ShieldRegenTimer")
	if t:
		t.stop()
		t.wait_time = _player.shield_recharge_seconds
		t.start()


func _recharge() -> void:
	if _player.shield >= _player.max_shield:
		return
	_player.shield += 1
	_player.emit_shield_changed()
	var t: Timer = _player.get_node("ShieldRegenTimer")
	if t:
		if _player.shield >= _player.max_shield:
			t.stop()
		else:
			t.stop()
			t.wait_time = _player.shield_recharge_seconds
			t.start()
