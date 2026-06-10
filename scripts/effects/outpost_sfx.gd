extends Node

# Outpost UI action SFX (Roman 2026-06-10). Non-positional one-shots on the SFX bus, played when the
# player completes an action in the outpost/manage-ship UI. Same static-helper shape as weapon_sfx /
# enemy_sfx. Kinds map to the asset filenames:
#   "equip"   — buy/equip a weapon or part
#   "unequip" — stow/sell a stored item
#   "upgrade" — buy a Mk upgrade
#   "repair"  — hull repair + the other restore services (shield/ammo/super refill)
#
#   OutpostSfx.play("equip")

const CLIPS := {
	"equip": [preload("res://Sound/outpost/equip.ogg")],
	"unequip": [preload("res://Sound/outpost/unequip.ogg")],
	"upgrade": [preload("res://Sound/outpost/upgrade.ogg")],
	"repair": [
		preload("res://Sound/outpost/repair_1.ogg"),
		preload("res://Sound/outpost/repair_2.ogg"),
	],
}

const VOLUME_DB: float = -3.0


static func play(kind: String) -> void:
	var pool: Array = CLIPS.get(kind, [])
	if pool.is_empty():
		return
	var clip: AudioStream = pool[randi() % pool.size()]
	if clip == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = clip
	p.volume_db = VOLUME_DB
	p.bus = "SFX"
	tree.root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
