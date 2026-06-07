extends Object

# Faction system data + spawn-overlay application (M6b, design §8). A faction =
# {pool, exclusives, modifier_components, stat_mods, weapon_mods, tint, lore_name}.
# The modifier rides ENTIRELY on the M6a component framework (§3) + the M6a.2 Weapon
# axes — no new per-faction machinery, which was the payoff of sequencing those first.
#
# LIVE: the producer picks a faction per level (main.gd / WaveGen.build), restricts the
# pool (Roster faction filter via ENEMY_TAGS + allowed_in), and the director calls
# apply() per spawn. core_pool/exclusives in data() stay [] — pool restriction is driven
# by ENEMY_TAGS, not those lists (kept for reference / the end-state per-faction sets).
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
# Zealot's firecore lane-hazard drop payload (the zealot DropFirecore Emitter spawns it
# on death). The ResourceLoader.exists guard in build_components stays as a safety net.
const FIRECORE_HAZARD_PATH := "res://scenes/enemies/firecore_hazard.tscn"

enum Id { SUPREMACY, PRIVATEER, CORPORATE, ZEALOT }

# Per-enemy faction tag (from the §12 redline, docs/m6b_faction_tagging_2026-06-06.md).
# `home` = the faction that owns the art/identity. `universal` = a core hull that, as a
# stopgap, overlays into ANY faction's level (themed by the modifier+tint); exclusives
# appear only in their home faction. Pool restriction: an enemy is allowed in faction F
# if universal OR home == F. (END-STATE: drop universals, each faction owns its set.)
const ENEMY_TAGS := {
	"res://scenes/enemies/core/enemy_dart.tscn": {"home": Id.PRIVATEER, "universal": true},
	"res://scenes/enemies/core/enemy_drifter.tscn": {"home": Id.ZEALOT, "universal": true},
	"res://scenes/enemies/core/enemy_spitter.tscn": {"home": Id.ZEALOT, "universal": true},
	"res://scenes/enemies/core/enemy_bomb_drone.tscn": {"home": Id.SUPREMACY, "universal": true},
	"res://scenes/enemies/core/enemy_weaver.tscn": {"home": Id.CORPORATE, "universal": true},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"home": Id.CORPORATE, "universal": true},
	"res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/core/enemy_crystal.tscn": {"home": Id.SUPREMACY, "universal": true},
	"res://scenes/enemies/core/enemy_cutter.tscn": {"home": Id.PRIVATEER, "universal": true},
	"res://scenes/enemies/core/enemy_bomber.tscn": {"home": Id.CORPORATE, "universal": true},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"home": Id.SUPREMACY, "universal": true},
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_sapper.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_strafer.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_gunship.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_rocket.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_firecore_drone.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_firecore_cruiser.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_burner.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn": {"home": Id.SUPREMACY, "universal": false},
}


# True if `scene_path` may appear in faction F's level (universal OR home == F). Untagged
# enemies are allowed everywhere (safe default — e.g. mines/asteroids/bosses/hazards).
static func allowed_in(scene_path: String, faction: int) -> bool:
	if faction < 0:
		return true
	var t: Variant = ENEMY_TAGS.get(scene_path, null)
	if t == null:
		return true
	return bool(t.get("universal", false)) or int(t.get("home", -1)) == faction


# Deterministic primary faction for a combat level (sector progression + run-seed).
static func pick_for_level(sector_depth: int, level_index: int, run_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run_seed) + sector_depth * 101 + level_index * 17
	return rng.randi() % 4


# Privateer is THE overlay faction (§8): its tough units sprinkle into other factions'
# levels. MVP = re-theme a spawn as a privateer interloper (tough + green) by chance.
# (The full "secondary pool DRAW" of an actual privateer unit is a later refinement.)
const PRIVATEER_OVERLAY_CHANCE := 0.12

static func effective_faction_for_spawn(primary: int) -> int:
	if primary != Id.PRIVATEER and primary >= 0 and randf() < PRIVATEER_OVERLAY_CHANCE:
		return Id.PRIVATEER
	return primary


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
				"stat_mods": {}, "weapon_mods": {"fire_rate_mult": 0.7, "bullet_speed_mult": 1.25},
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
	# Faction TINT is no longer applied (Roman 2026-06-06): per-faction SPRITES convey
	# faction identity, so a runtime modulate would just wash out the art. The `tint`
	# field stays in data() for reference (codex/UI) but is not stamped on the enemy.
	# Stat mods — tough HP (privateer).
	var sm: Dictionary = d.get("stat_mods", {})
	var hp_mult: float = float(sm.get("hp_mult", 1.0))
	if hp_mult != 1.0 and "max_health" in enemy:
		enemy.max_health = int(round(float(enemy.max_health) * hp_mult))
		if "health" in enemy:
			enemy.health = enemy.max_health
	# Weapon mods. Faster fire (supremacy): smaller interval = faster. Projectile
	# speed/damage mults COMPOUND onto the per-enemy fields (*=) so they stack with
	# sector modifiers; shoot_pattern applies them (speed clamped) to each bullet.
	var wm: Dictionary = d.get("weapon_mods", {})
	var fr: float = float(wm.get("fire_rate_mult", 1.0))
	if fr != 1.0:
		if "fire_interval_min" in enemy:
			enemy.fire_interval_min *= fr
		if "fire_interval_max" in enemy:
			enemy.fire_interval_max *= fr
	var bsm: float = float(wm.get("bullet_speed_mult", 1.0))
	if bsm != 1.0 and "bullet_speed_mult" in enemy:
		enemy.bullet_speed_mult *= bsm
	var bdm: float = float(wm.get("bullet_damage_mult", 1.0))
	if bdm != 1.0 and "bullet_damage_mult" in enemy:
		enemy.bullet_damage_mult *= bdm
	# Modifier components — Shield (corporate) / DropFirecore Emitter (zealot).
	var comps: Array = build_components(id)
	if not comps.is_empty() and "components" in enemy:
		var existing: Array = (enemy.components if enemy.components is Array else [])
		enemy.components = existing + comps
