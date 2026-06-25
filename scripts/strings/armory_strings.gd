extends Object

# Armory codex strings — display blurbs for player items, keyed by PartCatalog
# factory-name. The display NAME comes from the part itself (part.display_name);
# this file holds the codex BLURB (the genuinely-missing content). Mirror of the
# codex_strings.gd convention: extends Object, preload-referenced (NOT class_name —
# headless class-cache safety), const dict + static helper with a safe fallback.
#
# Authoritative-vs-mirror call (docs/armory_string_expansion_2026-06-08.md):
# MIRROR for the first pass — names stay inline on the parts (load-bearing for the
# shop/HUD + the .tres copy-back); the Armory reads the name off the part and the
# blurb from here. Passive-module blurbs slot in here when that layer is built.

const CODEX := {
	# --- Primary cannons (CANNON) ---
	"_make_basic_blaster": "Standard-issue energy repeater. Infinite ammo and a dependable cadence — the permanent spine of every loadout.",
	"_make_heavy_blaster": "Slow, heavy energy slugs that hit hard per shot. The cadence quickens at high Mk for a punishing top-tier rhythm.",
	"_make_autocannon": "A spin-up kinetic cannon — a beat of barrel-wind, then a high-rate stream. Metered ammo, devastating uptime once it's turning.",
	"_make_minigun": "A hitscan bullet hose at full rotary speed. Chews the first hull in its lane the instant the trigger drops — metered ammo, instant gratification.",
	"_make_rotary_laser": "A spun-up laser repeater: a brief charge, then a relentless cascade of bolts.",
	"_make_wave_gun": "Fires a widening energy wave that pierces chaff. Mk broadens it into a screen-spanning sweep.",
	"_make_laser_beam": "Auto Laser — alternating twin energy bolts from the nose. Steady, no-ammo precision fire.",
	"_make_spread_cannon": "Fans a volley of bolts across an arc. Mk adds bolts — point-blank crowd control.",
	# --- Secondaries (HARDPOINT_WING) ---
	"_make_rocket_pod": "Dumb-fire rockets from the wing ports — straight-line ordnance, alternating tubes, in timed bursts.",
	"_make_seeking_missile": "Tracks the nearest enemy and runs it down. Slow cadence, heavy payload.",
	"_make_anti_ship_missile": "A heavy seeker that prefers the LARGEST target on screen. Half the ammo, an enormous hit.",
	"_make_swarm_launcher": "Releases a salvo of homing micro-missiles that fan out to distinct targets and detonate on contact. Mk adds two missiles per level.",
	"_make_particle_beam": "A continuous particle lance that shreds chaff and stalls against tough hulls. Width grows with Mk.",
	"_make_side_pods": "Ammo Pods — extra forward muzzles that fire alongside your primary. Mk adds pods.",
	"_make_intercept_drones": "Spinning ablative drones orbit your ship and soak incoming bullets — each takes a few hits before popping (Mk adds +1 hit). They respawn each level; once gone, gone for the level. (A MODULE now, moved off the secondary slot.)",
	"_make_drone_swarm": "Combat Drones — deploys a timed wing of autonomous drones that fire on bosses first, then the nearest threat.",
	# --- Super (DEVICE_BAY_1) ---
	"_make_smart_bomb": "The panic button. A shockwave that ignores shields and clears the screen of chaff and ordnance; auto-fires to save you from a lethal hit. Charges are bought at outposts — the only super.",
	# --- Shift modes (SHIFT_MODE) ---
	"_make_focus_mode": "FOCUS stance (hold Shift). Slows you to a precise crawl with a pinpoint hitbox for threading dense fire. The default stance.",
	"_make_phase_shift": "PHASE stance (tap Shift). A short intangible blink — pass through bullets and ships, no offense, no screen-clear. Charges refill by killing enemies.",
	"_make_hyper_mode": "HYPER stance (hold Shift). Overdrive: +10% fire rate and unlimited ammo while the bar holds. Recharges only when idle — can't re-engage until full.",
	# --- Engines (ENGINE) ---
	"_make_basic_engine": "Main Engine — your baseline thrust. Mk raises top speed toward the clarity ceiling.",
	"_make_vectoring_engine": "Vectoring thrusters — crisper handling and a higher speed band.",
	# --- Passive Modules (MODULE bay — automatic, no-input) ---
	"_make_shield_core": "Shield Core — powers your charge-pool shield. The bay's default Core; drop it for a free module slot and fly shieldless, a deliberate glass cannon. Mk adds shield charges.",
	"_make_overcharge_core": "Pushes primary damage harder (+10%, rising to +30% by Mk) at the cost of one max shield charge. Teeth over armor — a natural fit for the shieldless build.",
	"_make_siphon_core": "Bleeds staying power from your kills: every Nth enemy destroyed restores one shield charge — every 10th at Mk.1, down to every 2nd at Mk.9. Aggression as sustain.",
	"_make_repair_nanites": "Regrows hull mid-fight once you've gone a few seconds undamaged — a pip every 12s, quickening to 4s at Mk.9. Caps just short of full, so it rewards disengaging, not facetanking.",
	"_make_ablative_plating": "Layered plates shrug off every Nth hull hit outright — no dice, pure rhythm. Every 6th hit at Mk.1, down to every 2nd at Mk.9.",
	"_make_targeting_computer": "Primary fire gains a crit chance for double damage — crit bolts streak purple so you can read the hit. Crit rate climbs 10% → 30% by Mk.",
	"_make_overclock_core": "Hold the trigger and your fire-rate winds up to a cap; let off and it spools back down. Rewards sustained pressure on a single target. +15% → +45% at full ramp by Mk.",
	"_make_system_delimiter": "Strips the safety governors as your hull falls: fire-rate AND damage surge the closer you are to death, maxing at 1 hull — nothing at full health. A comeback weapon. +20% → +60% by Mk.",
	"_make_reinforced_hull": "Bolts extra plating onto the hull — +1 pip per Mk, up to +8. At Mk.9 repairs also cost 30% less. The bay's basic survivability slot.",
	"_make_thrusters": "Auxiliary thrusters stacked on your engine — +3% move speed per Mk (to +27%), still capped at the readability ceiling. Dodging room without an engine swap.",
	"_make_shield_capacitor": "Recharges your shield faster and sooner — a shorter delay after a hit plus a quicker per-charge tick. With a Shield Core, it makes the shield a renewable resource.",
	"_make_backup_shield_capacitor": "An emergency cell that fires once per level: the first time your shield drops, it instantly dumps a slice of your max charges back in. 5% at Mk.1, rising 5% per Mk. Buys you one free panic moment a level.",
	"_make_reflective_shield": "Tunes the shield to bounce back: every Nth bullet it absorbs is reflected into the playfield at the nearest enemy, reusing your primary's bolt. Every 6th hit at Mk.1, tightening to every 2nd at Mk.9. Turns a defensive stance into chip damage.",
	"_make_micro_fabricator": "An onboard printer that runs between fights: clearing a level restocks a slice of your max primary and secondary ammo — never past the cap. 5% at Mk.1, +5% per Mk. Keeps metered weapons fed without an outpost stop.",
	"_make_energy_routers": "Reroutes power the moment you stop firing: while the trigger's idle, your shield's regen delay shortens and its charge-ticks come faster. Hold fire and it reverts to the slow baseline. 20% faster idle regen at Mk.1, up to 60% at Mk.9 — pairs naturally with a Shield Capacitor.",
	"_make_blaster_smart_mount": "Slaves your Blaster to a tracking turret: it auto-fires at the nearest enemy in a 120° front arc while you fly + work your Primary by hand. Disables Q-swap to the blaster. Mk speeds the traverse and tightens the spread.",
	"_make_primary_smart_mount": "Slaves your Primary to a tracking turret: it auto-fires at the nearest enemy in a 120° front arc while you fly + keep your Blaster on manual. Regen lasers hold until fully recharged, then loose a full burst. Disables Q-swap to the primary. Mk speeds traverse + tightens spread. Run both mounts and you never touch the trigger.",
}


static func codex_for(factory: String) -> String:
	return String(CODEX.get(factory, ""))
