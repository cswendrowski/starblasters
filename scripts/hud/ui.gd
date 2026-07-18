extends MarginContainer

# HUD root shell. The HUD was decomposed into self-binding widget scenes under
# scenes/hud/ (2026-07-15): shield/hull/system/mode/weapon/wave widgets find
# the player (via the "player" group) and the wave director on their own, and
# each owns its layout — move/edit them in the editor (scenes/ui.tscn places
# them; their internals live in their own .tscn files).
#
# This script only keeps what is genuinely HUD-global:
#   - the bounty readout (main.gd pushes values via update_score)
#   - the HologramHUD shell (damage shake, flicker in/out, death overlay)

const HologramHUDCls = preload("res://scripts/hud/hologram_hud.gd")

var _bounty_value_lbl: Label = null
var hologram_hud = null


func _ready() -> void:
	_bounty_value_lbl = $HUDElements/BountyValue

	hologram_hud = HologramHUDCls.new()
	hologram_hud.name = "HologramHUD"
	hologram_hud._hud_root = self
	add_child(hologram_hud)


# Widgets self-bind; this only wires the hologram shell (damage shake + death
# overlay need the player's damaged/died signals).
func bind_player(player) -> void:
	if hologram_hud:
		hologram_hud.bind_player(player)


func update_score(value) -> void:
	if _bounty_value_lbl:
		_bounty_value_lbl.text = "%d" % int(value)


func flicker_in(duration: float = 0.6) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_in"):
		hologram_hud.flicker_in(duration)


func flicker_out(duration: float = 0.5) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_out"):
		hologram_hud.flicker_out(duration)
