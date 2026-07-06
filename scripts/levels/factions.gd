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
const FIRECORE_HAZARD_PATH := "res://scenes/enemies/factions/zealot/firecore_hazard.tscn"
# Shared livery recolor shader (same one the player hull uses) — applied at spawn to any enemy
# carrying a "Livery" sprite layer, tinted by the active level faction (apply_livery below).
const LIVERY_SHADER = preload("res://scenes/player/livery_color.gdshader")
# Match the player's livery blend: player.tscn's Livery material bakes opacity 0.8 (the shader's
# darken strength). Enemies were running 1.0 (max darken → too dark); keep them in sync here.
const LIVERY_OPACITY := 0.8

enum Id { SUPREMACY, PRIVATEER, CORPORATE, ZEALOT }

# Per-enemy faction tag (from the §12 redline, docs/m6b_faction_tagging_2026-06-06.md).
# `home` = the faction that owns the art/identity. `universal` = a core hull that, as a
# stopgap, overlays into ANY faction's level (themed by the modifier+tint); exclusives
# appear only in their home faction. Pool restriction: an enemy is allowed in faction F
# if universal OR home == F. (END-STATE: drop universals, each faction owns its set.)
const ENEMY_TAGS := {
	"res://scenes/enemies/core/enemy_core_s_dart.tscn": {"home": Id.SUPREMACY, "universal": true, "allowed_in": [Id.SUPREMACY]},  # Roman 2026-07-06: dart is Supremacy-only now (off privateer/corpo)
	"res://scenes/enemies/core/enemy_core_s_flechette.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # NEW core flechette (off the dart)
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"home": Id.ZEALOT, "universal": false},
	# Roman art rework 2026-06-16: retro→acolyte, run→drifter (renamed in place, same UID).
	"res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"home": Id.ZEALOT, "universal": false},
	# New zealot chaff/elites (Roman 2026-06-16) — Enemy-Bench-configurable, not yet in the wave roll.
	"res://scenes/enemies/factions/zealot/enemy_z_s_crook.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_pilgrim.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_censer.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_cross.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_rebuker.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_s_spear.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/boss_z_l_shepherd.tscn": {"home": Id.ZEALOT, "universal": false},
	# enemy_bomb_drone PULLED 2026-06-14 (Roman — rework pending); roster entry also removed.
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_m_widow.tscn": {"home": Id.CORPORATE, "universal": false},  # A-110 Widow → corporate (Roman 2026-06-20); scene moved privateer/enemy_p_m_widow → corporate/enemy_c_m_widow 2026-06-23.
	# New corporate small units (Roman 2026-07-06) — Enemy-Bench-configurable, not yet in the wave roll.
	"res://scenes/enemies/factions/corporate/enemy_c_s_archer.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_s_specter.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/core/enemy_core_bomber.tscn": {"home": Id.CORPORATE, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # B-220 core bomber (corp+priv, per its TailGunGlow tints)
	"res://scenes/enemies/core/enemy_core_bomber_thin.tscn": {"home": Id.CORPORATE, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # thin bomber variant — core (corp+priv)
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"home": Id.SUPREMACY, "universal": true},
	"res://scenes/enemies/core/enemy_core_m_minelayer.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.SUPREMACY, Id.PRIVATEER, Id.CORPORATE]},  # core minelayer (Zealot gets its own later)
	"res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.PRIVATEER]},  # core Falchion (was Hornet/p_s_green), privateer-only for now
	"res://scenes/enemies/core/enemy_core_s_cobra.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # CF-9D Cobra core (corpo twin enemy_c_s_gray cut)
	"res://scenes/enemies/core/enemy_core_s_caltrop.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # Caltrop core (corpo twin enemy_c_s_drop cut)
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/core/enemy_core_s_jet.tscn": {"home": Id.PRIVATEER, "universal": true, "allowed_in": [Id.CORPORATE, Id.PRIVATEER]},  # core Jet
	"res://scenes/enemies/factions/privateer/enemy_p_m_wing.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_s_sapper.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"home": Id.SUPREMACY, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"home": Id.SUPREMACY, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"home": Id.SUPREMACY, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn": {"home": Id.CORPORATE, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/privateer/enemy_p_m_rocket.tscn": {"home": Id.PRIVATEER, "universal": false},
	"res://scenes/enemies/factions/corporate/enemy_c_l_hive.tscn": {"home": Id.CORPORATE, "universal": false},
	# Roman art rework 2026-06-16: firecore_drone→bloom, firecore_cruiser→helix (renamed, same UID).
	"res://scenes/enemies/factions/zealot/enemy_z_s_bloom.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_z_l_crusader.tscn": {"home": Id.ZEALOT, "universal": false},  # NEW large zealot capital
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/zealot/enemy_burner.tscn": {"home": Id.ZEALOT, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"home": Id.SUPREMACY, "universal": false},
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn": {"home": Id.SUPREMACY, "universal": false},
}


# True if `scene_path` may appear in faction F's level (universal OR home == F). Untagged
# enemies are allowed everywhere (safe default — e.g. mines/asteroids/bosses/hazards).
# Core-ship identity (2026-06-20): a tag may carry an optional "allowed_in": [Id…] whitelist —
# a universal enemy restricted to a subset of factions (e.g. the core Minelayer in Corp/Sup/Priv
# but not Zealot). When present, the faction must ALSO be in that list. Absent = unrestricted.
static func allowed_in(scene_path: String, faction: int) -> bool:
	if faction < 0:
		return true
	var t: Variant = ENEMY_TAGS.get(scene_path, null)
	if t == null:
		return true
	if not (bool(t.get("universal", false)) or int(t.get("home", -1)) == faction):
		return false
	var whitelist: Variant = t.get("allowed_in", null)
	if whitelist is Array:
		return faction in whitelist
	return true


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
				"modifier_components": [], "tint": LIVERY_COLOR[Id.SUPREMACY],
			}
		Id.PRIVATEER:
			return {
				"id": "privateer", "lore_name": "Vertarine Armada",
				"core_pool": [], "exclusives": [], "overlay": true,
				"stat_mods": {"hp_mult": 2.0}, "weapon_mods": {},
				"modifier_components": [], "tint": LIVERY_COLOR[Id.PRIVATEER],
			}
		Id.CORPORATE:
			return {
				"id": "corporate", "lore_name": "UltraGalactic Concerns",
				"core_pool": [], "exclusives": [], "overlay": false,
				"stat_mods": {}, "weapon_mods": {},
				"modifier_components": ["shield"], "tint": LIVERY_COLOR[Id.CORPORATE],
			}
		Id.ZEALOT:
			return {
				"id": "zealot", "lore_name": "Evantian Theocracy",
				"core_pool": [], "exclusives": [], "overlay": false,
				"stat_mods": {}, "weapon_mods": {},
				"modifier_components": ["firecore"], "tint": LIVERY_COLOR[Id.ZEALOT],
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
			# Tag drives the death-explosion routing (enemy_base.explode: firecore dropped ->
			# normal explosion, no drop -> ball). Without it the overlay path misclassified
			# every faction-driven drop (review fix 2026-06-10).
			em.tag = "firecore"
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
	# Faction bonuses apply ONLY to units whose HOME is this faction (Roman 2026-06-08):
	# universals + foreign units that appear in the level get NO overlay. So a privateer-home
	# dart in a corporate level is not corpo-shielded, and a faction's buffs never leak onto
	# other factions' units sharing the level. Untagged spawns (mines/asteroids/bosses) get
	# nothing either.
	var fpath: String = String(enemy.scene_file_path) if "scene_file_path" in enemy else ""
	var ftag: Variant = ENEMY_TAGS.get(fpath, null)
	if ftag == null or int(ftag.get("home", -1)) != id:
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
	# Weapon mods. Faster fire (supremacy): smaller interval = faster. Projectile SPEED mult
	# compounds onto the per-enemy field (*=); shoot_pattern applies it (clamped) to each bullet.
	# NOTE: faction bullet_damage_mult was REMOVED 2026-07-04 — player damage is flat 1 across the
	# board (see player.take_damage), so no faction changes per-hit damage. Difficulty is volume.
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
	# Modifier components — Shield (corporate) / DropFirecore Emitter (zealot).
	var comps: Array = build_components(id)
	if not comps.is_empty() and "components" in enemy:
		var existing: Array = (enemy.components if enemy.components is Array else [])
		# Don't stack the zealot overlay's CHANCE firecore drop onto an enemy that
		# already bakes a GUARANTEED firecore drop (retro/run/helix) — a guaranteed
		# drop doesn't need the extra roll (Roman 2026-06-07). Drop the overlay's
		# firecore emitter in that case; other overlay components still apply.
		var bakes_firecore: bool = false
		for c in existing:
			if _is_firecore_drop(c):
				bakes_firecore = true
				break
		# Per-enemy opt-out of the corporate Shield overlay (e.g. c_dart — a corporate
		# dart that shouldn't be shielded). Roman 2026-06-07.
		var no_shield: bool = ("faction_shield_exempt" in enemy) and bool(enemy.faction_shield_exempt)
		var to_add: Array = []
		for c in comps:
			if bakes_firecore and _is_firecore_drop(c):
				continue
			if no_shield and ("capacity" in c) and not ("payload" in c):
				continue   # skip the shield component for exempt enemies
			to_add.append(c)
		enemy.components = existing + to_add


# Recolor an enemy's Livery layer to the active level faction. Runtime auto-detect: ANY enemy
# carrying a "Livery" sprite (frame-2 of its 3-frame strip, mirroring the player hull) gets the
# faction's tint via the shared livery_color shader — no per-scene shader setup. The producer
# (director._spawn_enemy) calls this for EVERY spawn, BEFORE add_child, with the resolved level
# faction (or -1). Unlike apply(), livery is NOT home-gated: a foreign unit appearing in a
# faction's level wears that level's colors (Roman 2026-06-20). faction < 0 (no faction / boss /
# hazard) hides the Livery layer so it doesn't render an untinted overlay.
static func apply_livery(faction: int, enemy) -> void:
	if enemy == null:
		return
	var lv = enemy.get_node_or_null("Livery")
	if lv == null:
		return
	if faction < 0:
		lv.visible = false
		return
	var mat := ShaderMaterial.new()
	mat.shader = LIVERY_SHADER
	mat.set_shader_parameter("tint_color", data(faction).get("tint", Color(0.5, 0.5, 0.5)))
	mat.set_shader_parameter("opacity", LIVERY_OPACITY)   # match the player's livery blend
	mat.set_shader_parameter("fade", 1.0)                 # master visibility; enemy_base's death-fade tweens it to 0
	lv.material = mat
	lv.visible = true


# CENTRALIZED per-faction color (Roman 2026-06-21) — THE single source for a faction's color across
# EVERY visual overlay facet: livery (data().tint → apply_livery), tail-glow (apply_tailglow), and the
# codex UI. Edit HERE to recolor a faction everywhere. Privateer lime-green + corporate purple-pink are
# Roman's calls; supremacy crimson / zealot firecore-orange follow faction identity. Bright values so
# the WorldEnvironment bloom blooms the glow in-hue.
# CENTRALIZED faction colors (Roman 2026-06-21) — TWO separate per-faction palettes, each the single
# source for its facet. Edit HERE to recolor everywhere.
#   LIVERY_COLOR      — the hull LIVERY decal color (data().tint → apply_livery; + codex). 4 distinct.
#   MUZZLE_GLOW_COLOR — the faction's ENERGY color: muzzle flashes + tail-glow (apply_tailglow). Shared
#                       in pairs — Supremacy+Zealot = gold, Privateer+Corporate = lime. (Distinct from
#                       the livery color on purpose — a faction's paint ≠ its weapon energy.)
static var LIVERY_COLOR := {
	Id.SUPREMACY: Color.html("#ac3232"),  # red
	Id.PRIVATEER: Color.html("#4b692f"),  # green
	Id.CORPORATE: Color.html("#4972a9"),  # blue
	Id.ZEALOT:    Color.html("#76428a"),  # purple
}
static var MUZZLE_GLOW_COLOR := {
	Id.SUPREMACY: Color.html("#fbf236"),  # gold (Supremacy + Zealot)
	Id.ZEALOT:    Color.html("#fbf236"),  # gold
	Id.PRIVATEER: Color.html("#99e550"),  # lime (Privateer + Corporate)
	Id.CORPORATE: Color.html("#99e550"),  # lime
}


# The faction's hull-livery color (white fallback for no/unknown faction).
static func livery_color(faction: int) -> Color:
	return LIVERY_COLOR.get(faction, Color(1.0, 1.0, 1.0))


# The faction's ENERGY color — muzzle flashes + tail-glow (white fallback). Shared in pairs.
static func muzzle_glow_color(faction: int) -> Color:
	return MUZZLE_GLOW_COLOR.get(faction, Color(1.0, 1.0, 1.0))


# Tint an enemy's TailGunGlow layer to the active faction's signature bullet color (Roman 2026-06-21):
# the tail/engine glow then reads as the faction's projectiles (privateer lime-green, corpo purple-
# pink…). Mirrors apply_livery — runtime auto-detect of a "TailGunGlow" sprite, applied per spawn by
# the director. A multiply modulate (the layer is an emissive glow frame, not a screen-darken decal).
# faction < 0 leaves the layer's baked color (no faction context).
static func apply_tailglow(faction: int, enemy) -> void:
	if enemy == null or faction < 0:
		return
	var tg = enemy.get_node_or_null("TailGunGlow")
	if tg == null:
		return
	tg.modulate = muzzle_glow_color(faction)


# True if `c` is an Emitter that drops a firecore hazard on death — used to avoid
# stacking the zealot overlay's chance-drop onto an enemy that bakes a guaranteed one.
static func _is_firecore_drop(c) -> bool:
	if c == null:
		return false
	if not ("payload" in c and "trigger" in c):
		return false
	if c.payload == null:
		return false
	return int(c.trigger) == EmitterComponent.Trigger.DEATH \
		and str(c.payload.resource_path) == FIRECORE_HAZARD_PATH
