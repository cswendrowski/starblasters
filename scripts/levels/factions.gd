extends Object

# Faction system data + spawn-overlay application (M6b, design §8). A faction =
# {pool, exclusives, modifier_components, stat_mods, weapon_mods, tint, lore_name}.
# The modifier rides ENTIRELY on the M6a component framework (§3) + the M6a.2 Weapon
# axes — no new per-faction machinery, which was the payoff of sequencing those first.
#
# INERT until the producer/conductor picks a faction per level and populates the
# pools: nothing calls apply() yet, and core_pool/exclusives are empty pending the
# §12 content-tagging redline.
#
# Preload-referenced, NOT a global class_name (a new class_name isn't registered in
# headless --script until the cache regenerates; the director + tests would hit it).
# Design said `class_name Factions` — deviated to preload for headless safety, matching
# lane_traffic / weapon / beam_emitter.
#
# Four factions (Roman, LOCKED §8):
#   supremacy (Crimson Supremacy)      — faster fire   → weapon fire-rate multiplier
#   privateer (Vertarine Armada)       — tough + mixes → 2x HP; the OVERLAY faction
#   corporate (UltraGalactic Concerns) — shielded      → Shield component on every spawn
#   zealot    (Evantian Theocracy)     — drops firecore→ DropFirecore Emitter on death

const ShieldComponent = preload("res://scripts/enemies/components/shield_component.gd")
const EmitterComponent = preload("res://scripts/enemies/components/emitter_component.gd")
# Zealot's firecore lane-hazard drop payload — the scene is a later slice; until it
# exists the Emitter carries a null payload (inert, no crash).
const FIRECORE_HAZARD_PATH := "res://scenes/enemies/firecore_hazard.tscn"

enum Id { SUPREMACY, PRIVATEER, CORPORATE, ZEALOT }


static func id_key(id: int) -> String:
	match id:
		Id.SUPREMACY: return "supremacy"
		Id.PRIVATEER: return "privateer"
		Id.CORPORATE: return "corporate"
		Id.ZEALOT: return "zealot"
	return "supremacy"


# Faction record. core_pool/exclusives are empty pending the §12 tagging redline.
static func data(id: int) -> Dictionary:
	match id:
		Id.SUPREMACY:
			return {
				"id": "supremacy", "lore_name": "Crimson Supremacy",
				"core_pool": [], "exclusives": [], "overlay": false,
				"stat_mods": {}, "weapon_mods": {"fire_rate_mult": 0.7},
				"modifier_components": [], "tint": Color(1.0, 0.45, 0.45),
			}
		Id.PRIVATEER:
			return {
				"id": "privateer", "lore_name": "Vertarine Armada",
				"core_pool": [], "exclusives": [], "overlay": true,
				"stat_mods": {"hp_mult": 2.0}, "weapon_mods": {},
				"modifier_components": [], "tint": Color(0.55, 0.85, 0.6),
			}
		Id.CORPORATE:
			return {
				"id": "corporate", "lore_name": "UltraGalactic Concerns",
				"core_pool": [], "exclusives": [], "overlay": false,
				"stat_mods": {}, "weapon_mods": {},
				"modifier_components": ["shield"], "tint": Color(0.55, 0.7, 1.0),
			}
		Id.ZEALOT:
			return {
				"id": "zealot", "lore_name": "Evantian Theocracy",
				"core_pool": [], "exclusives": [], "overlay": false,
				"stat_mods": {}, "weapon_mods": {},
				"modifier_components": ["firecore"], "tint": Color(1.0, 0.6, 0.3),
			}
	return data(Id.SUPREMACY)


# Fresh modifier-component instances for a faction (stateful → one set per spawn).
static func build_components(id: int) -> Array:
	var out: Array = []
	match id:
		Id.CORPORATE:
			var sh = ShieldComponent.new()
			sh.capacity = 1   # "shielded" = a single regen charge
			out.append(sh)
		Id.ZEALOT:
			var em = EmitterComponent.new()
			em.trigger = EmitterComponent.Trigger.DEATH
			em.count = 1
			em.chance = 0.35   # drops a firecore by chance on death (§8)
			if ResourceLoader.exists(FIRECORE_HAZARD_PATH):
				em.payload = load(FIRECORE_HAZARD_PATH)
			out.append(em)
	return out


# Apply a faction's modifier to a freshly-instantiated enemy. MUST be called BEFORE
# add_child so enemy_base dups the attached components in _ready. INERT until the
# producer calls it. Privateer is applied per-spawn as a secondary overlay elsewhere.
static func apply(id: int, enemy) -> void:
	if enemy == null:
		return
	var d: Dictionary = data(id)
	# Tint (instant visual read).
	if enemy is CanvasItem:
		enemy.modulate = d.get("tint", Color.WHITE)
	# Stat mods — tough HP (privateer).
	var sm: Dictionary = d.get("stat_mods", {})
	var hp_mult: float = float(sm.get("hp_mult", 1.0))
	if hp_mult != 1.0 and "max_health" in enemy:
		enemy.max_health = int(round(float(enemy.max_health) * hp_mult))
		if "health" in enemy:
			enemy.health = enemy.max_health
	# Weapon mods — faster fire (supremacy): smaller interval = faster.
	var wm: Dictionary = d.get("weapon_mods", {})
	var fr: float = float(wm.get("fire_rate_mult", 1.0))
	if fr != 1.0:
		if "fire_interval_min" in enemy:
			enemy.fire_interval_min *= fr
		if "fire_interval_max" in enemy:
			enemy.fire_interval_max *= fr
	# Modifier components — Shield (corporate) / DropFirecore Emitter (zealot).
	var comps: Array = build_components(id)
	if not comps.is_empty() and "components" in enemy:
		var existing: Array = (enemy.components if enemy.components is Array else [])
		enemy.components = existing + comps
