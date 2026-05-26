class_name RunSave
extends Resource

# Serializable snapshot of Run autoload state. Written via ResourceSaver to
# user://run_save.tres on sector map entry; read back by Resume Patrol.
# Resources nested in Dictionaries/Arrays (loadout_snapshot Parts,
# inventory/weapon_storage Parts) round-trip as inline sub-resources.

@export var bounty: int = 0
@export var current_hull: int = 0
@export var max_hull: int = 0
@export var current_shield: int = 0
@export var max_shield: int = 0
@export var super_charges: int = 0
@export var max_super_charges: int = 3

@export var loadout_snapshot: Dictionary = {}
@export var inventory: Array = []
@export var weapon_storage: Array = []

@export var current_node_id: String = ""
@export var current_node_type: int = -1
@export var sector_modifiers: Array = []
@export var current_hazard_subtype: String = ""
@export var asteroid_bonus_bounty: int = 0
@export var combat_intro: String = ""
@export var current_stellar: Dictionary = {}

@export var ammo: int = -1
@export var secondary_ammo: int = -1
@export var secondary_ammo_max: int = -1

@export var visited_nodes: Array = []
@export var sectors_cleared: int = 0
@export var used_boss_scenes: Array = []
@export var combats_in_sector: int = 0
@export var enemies_killed: int = 0
@export var max_bounty_earned: int = 0
@export var run_distance: float = 0.0
@export var run_seed: int = 0

@export var hull_mk: int = 0
@export var armor_mk: int = 0
@export var thrusters_mk: int = 0
@export var self_repair_mk: int = 0
@export var shield_cap_mk: int = 0
@export var shield_recharge_mk: int = 0

@export var sector_map_cache: Dictionary = {}

# Weapons Phase 1 (2026-05-26): cannon pool + active index. cannon_pool[0]
# is the permanent Energy Blaster; further entries are owned replacement
# primaries with per-cannon `current_ammo` on the Part.
@export var cannon_pool: Array = []
@export var active_cannon_idx: int = 0
