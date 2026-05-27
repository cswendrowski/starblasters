class_name Strings
extends Object

# Central strings file — all user-visible text in one place.
# Static constants only; no instances needed.
# Format strings (containing %d / %s) stay as format strings — callers use
# Strings.FOO % value  or  Strings.FOO % [a, b].
#
# Sections:
#   ONBOARDING   — tutorial pages, buttons, icon labels
#   EVENTS       — signal event titles, bodies, choice labels, outcome messages
#   OUTPOST      — upgrade names/descs, service labels, toasts, UI chrome


# ===========================================================================
# ONBOARDING
# ===========================================================================

# Page titles and bodies.
const ONBOARDING_CONTROLS_TITLE := "Controls"
const ONBOARDING_CONTROLS_BODY := "Arrow Keys — move.\nSpace / Z — fire primary cannon.\nC — fire secondary hardpoint weapon.\nX — super weapon (limited charges).\nShift — Focus mode: slower precise movement; shows your hitbox.\nQ — swap between primary cannons (if you own more than one).\nEsc — pause."

const ONBOARDING_PARTS_TITLE := "Parts & Marks"
const ONBOARDING_PARTS_BODY := "Your ship is a hull stuffed with slotted parts: Cannon, Engine, Shield, Wings, Tail.\n\nEvery part has a Mark — Mk.1 through Mk.9. Higher Mk = stronger: more damage, more speed, deeper shield pool. Mk values are stamped on the part card.\n\nOutposts sell upgraded marks of parts you already own; pick up doubles to climb the curve. A Mk.9 build by sector's end is the goal."

const ONBOARDING_SHIELDS_TITLE := "Shields & Hull"
const ONBOARDING_SHIELDS_BODY := "Your ship has two layers of integrity.\n\nThe SHIELD bar at the top absorbs incoming fire. When it runs out, hits bleed into your HULL.\n\nThe diamond pips next to it are your hull. When the last pip falls, your ship is gone — there's no second chance in a run."

const ONBOARDING_SHIELD_REGEN_TITLE := "Shield Regen"
const ONBOARDING_SHIELD_REGEN_BODY := "Shields regenerate automatically a couple of seconds after the last hit.\n\nIf you can disengage for a beat — duck behind cover, juke away from a barrage — your shield will come back. The TAIL part on your ship determines how fast."

const ONBOARDING_BOUNTY_TITLE := "Bounty"
const ONBOARDING_BOUNTY_BODY := "Every enemy you destroy drops Bounty Credits. You can see your running total at the top-right of the HUD.\n\nSpend bounty at Friendly Outposts on new parts and hull repairs, or on Junk Traders for sketchier deals. Survive deeper into a run and the prices climb — but so do the rewards."

const ONBOARDING_WAVES_TITLE := "Waves"
const ONBOARDING_WAVES_BODY := "Combat levels are split into waves. A banner pops at the start of each: WAVE 1 / 7, WAVE 2 / 7, and so on.\n\nMid-level, the wave count tells you how close you are to clearing. The last two waves of every level are the loudest — keep something in reserve."

const ONBOARDING_SECTOR_MAP_TITLE := "Sector Map"
const ONBOARDING_SECTOR_MAP_BODY := "Your patrol covers three sectors. Each sector is a branching map — pick your path forward through a row of nodes, then face the sector boss at the end.\n\nAfter the boss, the next sector opens. Clear all three to complete the mission."

const ONBOARDING_NODE_TYPES_TITLE := "Node Types"
const ONBOARDING_NODE_TYPES_BODY := "Combat — fight a wave of enemies for bounty.\nOutpost — spend bounty on parts, ammo, and hull repairs.\nSignal — unknown contact; random reward or risk.\nHazard — fly through a dangerous field for a bonus.\nBoss — the sector commander. Defeat it to advance."

const ONBOARDING_MISSION_TITLE := "Mission Briefing"
const ONBOARDING_MISSION_BODY := "Your mission is to patrol three sectors, hunting down the wanted pirates and corporate privateers lurking there. Each one you take out is worth bounty, and each bounty will help you secure the next one a little more easily. Search the systems, blast pirates until you figure out where the worst of them are, and eliminate them.\n\nGood luck, Starblaster!"

# Navigation buttons.
const ONBOARDING_BTN_BACK := "Back"
const ONBOARDING_BTN_NEXT := "Next"
const ONBOARDING_BTN_SKIP := "Skip Tutorial"
const ONBOARDING_BTN_BEGIN := "Begin Patrol"

# Sector-map page icon labels.
const ONBOARDING_ICON_COMBAT := "Combat"
const ONBOARDING_ICON_OUTPOST := "Outpost"
const ONBOARDING_ICON_SIGNAL := "Signal"
const ONBOARDING_ICON_HAZARD := "Hazard"
const ONBOARDING_ICON_BOSS := "Boss"


# ===========================================================================
# EVENTS  (signal_event.gd)
# ===========================================================================

# ---- Event titles and bodies ----

const EVENT_AMBUSH_TITLE := "Ambush!"
const EVENT_AMBUSH_BODY := "Warning lights flare in your periphery: active scan warnings. Sensors pick them up a second later — multiple incoming signatures closing from behind!"

const EVENT_NANO_CLOUD_TITLE := "Drifting Nano Cloud"
const EVENT_NANO_CLOUD_BODY := "Sensors indicate micro-energy signatures. You squint, and can see a glittering cloud moving like a swarm of bugs. A nano cloud?"

const EVENT_JUNK_TRADER_TITLE := "Junk Trader"
const EVENT_JUNK_TRADER_BODY := "An old cargo hauler drifts through space, a makeshift drydock bay built into its side. A hacked transponder signal bleats out garbled promises of top quality repairs and exciting deals."

const EVENT_MINER_TITLE := "Freespace Miner"
const EVENT_MINER_BODY := "Your comms light up as a wandering mining ship calls for your attention: they've found high-value minerals, but the asteroids are too tough for their mining lasers. Proper fighter weapons would crack them."

const EVENT_WRECK_TITLE := "Wrecked Starfighter"
const EVENT_WRECK_BODY := "A burnt-out fighter tumbles end over end through the void, hull cracked and lockers spilling debris. Worth a closer look."

const EVENT_SALVAGE_TITLE := "Salvage Cache"
const EVENT_SALVAGE_BODY := "Sensors flag a battered container tumbling through the dust — military markings, locks half-melted. Worth cracking open."

# Fallback title when no event loaded.
const EVENT_UNKNOWN_TITLE := "Unknown Signal"

# ---- Choice labels ----

const CHOICE_AMBUSH_FIGHT := "Fight through (combat)"
const CHOICE_AMBUSH_EVADE := "Evasive maneuvers (risky)"

const CHOICE_NANO_FLY := "Fly into it (risk/reward)"
const CHOICE_NANO_AVOID := "Avoid it"

const CHOICE_JUNK_SELL := "Sell a part (+bounty)"
const CHOICE_JUNK_TRADE := "Trade a part (random outcome)"
const CHOICE_JUNK_REPAIR := "Repair hull (-30 bounty, +3 hull)"
const CHOICE_JUNK_AMMO := "Buy ammo (-15 bounty, +500 rounds)"
const CHOICE_JUNK_LEAVE := "Leave"

const CHOICE_MINER_AGREE := "Agree (asteroid run, +bounty per rock)"
const CHOICE_MINER_REFUSE := "Refuse"

const CHOICE_WRECK_BOUNTY := "Claim bounty"
const CHOICE_WRECK_WEAPON := "Scavenge weapon"
const CHOICE_WRECK_UPGRADE := "Scavenge upgrade"
const CHOICE_WRECK_AMMO := "Scavenge ammo (+25% of max)"
const CHOICE_WRECK_LEAVE := "Leave it be"

const CHOICE_SALVAGE_SALVAGE := "Salvage the cache (random reward)"
const CHOICE_SALVAGE_LEAVE := "Leave it adrift"

# ---- Outcome messages ----
# Format strings: use  Strings.FOO % value  at call site.

const OUTCOME_AMBUSH_EVADE_CLEAN := "Evaded — escaped cleanly!"
const OUTCOME_AMBUSH_EVADE_HIT := "Evaded — hull grazed! -1 hull"

const OUTCOME_NANO_AVOID := "Course corrected. No effect."
const OUTCOME_NANO_DAMAGE := "Hostile nanites! -%d hull"
const OUTCOME_NANO_REPAIR := "Repair nanites. +%d hull"
const OUTCOME_NANO_UPGRADE := "Beneficial swarm! Upgraded %s"
const OUTCOME_NANO_UPGRADE_MAXED := "Beneficial swarm — but nothing upgradable!"
const OUTCOME_NANO_AMMO := "Nanites manufactured ammo! +%d rounds"

const OUTCOME_JUNK_NO_CARGO_SELL := "No spare parts in cargo to sell."
const OUTCOME_JUNK_SOLD := "Sold %s for %d bounty"
const OUTCOME_JUNK_NO_CARGO_TRADE := "No spare parts in cargo to trade."
const OUTCOME_JUNK_TRADED := "Traded %s → %s (Mk %s)"
const OUTCOME_JUNK_NO_SLOT := "Trader has nothing for that slot."
const OUTCOME_JUNK_REPAIR_BROKE := "Not enough bounty (need 30)."
const OUTCOME_JUNK_REPAIRED := "Patched up. -30 bounty, +3 hull"
const OUTCOME_JUNK_NO_RUN := "Comms dropped."
const OUTCOME_JUNK_NO_AMMO_WEAPON := "No ammo-fed weapon to refill."
const OUTCOME_JUNK_AMMO_BROKE := "Not enough bounty (need %d)."
const OUTCOME_JUNK_AMMO_LOADED := "Crates loaded. -%d bounty, +%d rounds"
const OUTCOME_JUNK_LEAVE := "You break orbit — the hauler drifts on."

const OUTCOME_MINER_REFUSE := "Channel closed."

const OUTCOME_WRECK_BOUNTY_FALLBACK := "Bounty tagged. +10 bounty"
const OUTCOME_WRECK_BOUNTY := "Bounty tagged. +%d bounty"
const OUTCOME_WRECK_AMMO := "Ammo crates salvaged: "
const OUTCOME_WRECK_AMMO_FULL := "Lockers already topped up."
const OUTCOME_WRECK_LEAVE := "You give the wreck a wide berth."
const OUTCOME_WRECK_NO_RUN := "Comms dropped."

const OUTCOME_SALVAGE_LEAVE := "You pass on the cache."
const OUTCOME_SALVAGE_NO_RUN := "Cache empty."
const OUTCOME_SALVAGE_UPGRADE := "Salvaged tech upgrade! %s → Mk %d"
const OUTCOME_SALVAGE_NO_WEAPONS := "Cache held no compatible weapons."
const OUTCOME_SALVAGE_AMMO_INERT := "Cache held only inert ammo crates."
const OUTCOME_SALVAGE_AMMO := "Ammo refilled! "

# Ammo-line fragments (joined with ", ").
const AMMO_FRAGMENT_MG := "MG +%d rounds"
const AMMO_FRAGMENT_SECONDARY := "Secondary +%d"
const AMMO_FRAGMENT_SECONDARY_FULL := "Secondary full (%d)"

# Part-label helpers.
const PART_LABEL_FORMAT := "Mk.%d %s"
const PART_LABEL_UNKNOWN := "unknown part"
const PART_SLOT_NAME_PRIMARY := "Primary"
const PART_SLOT_NAME_SECONDARY := "Secondary"
const PART_SLOT_EMPTY := "(empty)"

# Weapon-swap modal (in _offer_weapon_swap).
const EVENT_SWAP_BODY := "SALVAGED: %s.\nSwap your current %s (%s)?"
const EVENT_SWAP_BTN := "Swap → %s"
const EVENT_SWAP_KEEP := "Keep current — stow %s"
const OUTCOME_SWAP_EQUIPPED := "Equipped %s as %s."
const OUTCOME_SWAP_STOWED := "Stowed %s in cargo."

# Continue button after any event resolves.
const BTN_SECTOR_MAP := "Sector Map"


# ===========================================================================
# OUTPOST  (outpost.gd)
# ===========================================================================

# ---- Upgrade card names and descriptions ----

const UPGRADE_HULL_NAME := "Hull"
const UPGRADE_HULL_DESC := "+1 max hull pip per Mk (base 3)."

const UPGRADE_THRUSTERS_NAME := "Thrusters"
const UPGRADE_THRUSTERS_DESC := "+3% movement speed per Mk."

const UPGRADE_SELF_REPAIR_NAME := "Self Repair"
const UPGRADE_SELF_REPAIR_DESC := "+1 hull pip on sector map return."

const UPGRADE_SHIELD_CAP_NAME := "Shield Capacity"
const UPGRADE_SHIELD_CAP_DESC := "+2 max shield HP per Mk (base 10)."

# ---- Service button base labels ----

const SERVICE_HULL_REPAIR := "Hull Repair  +1 pip"
const SERVICE_SHIELD_REFILL := "Shield Refill"
const SERVICE_PRIMARY_AMMO := "Primary Ammo"
const SERVICE_SECONDARY_AMMO := "Secondary Ammo"
const SERVICE_SUPER_CHARGE := "Super Charge  +1"

# ---- Service button dynamic-state suffixes ----
# Appended to the base_label via "%s %s" in _apply_service_button_state.

const SERVICE_SUFFIX_NO_SHIP := "(no ship)"
const SERVICE_STATE_HULL_FULL := "Hull Full"
const SERVICE_SUFFIX_NO_SHIELD := "(no shield)"
const SERVICE_STATE_SHIELDS_FULL := "Shields Full"
const SERVICE_SUFFIX_FREE := "(FREE)"
const SERVICE_SUFFIX_NO_RUN := "(no run)"
const SERVICE_SUFFIX_BLASTER_INFINITE := "(Blaster, infinite)"
const SERVICE_SUFFIX_NO_PRIMARY_AMMO := "(no primary ammo)"
const SERVICE_SUFFIX_AUTO_REGEN := "(auto-regen)"
const SERVICE_STATE_AMMO_FULL := "%s  Full"
const SERVICE_SUFFIX_REFILL_COST := "Refill (%d)"
const SERVICE_SUFFIX_NONE_EQUIPPED := "(none equipped)"
const SERVICE_SUFFIX_NEED := "+%d (need %d)"
const SERVICE_SUFFIX_PARTIAL := "+%d (%d, partial)"
const SERVICE_SUFFIX_AMMO_COST := "+%d (%d)"
const SERVICE_STATE_SUPER_NONE := "Super  (none equipped)"
const SERVICE_STATE_SUPER_FULL := "Super  Full"

# ---- Toast messages ----

const TOAST_UPGRADE_PURCHASED := "Upgrade purchased"
const TOAST_EQUIPPED := "EQUIPPED"
const TOAST_PRIMARY_REFILLED := "Primary refilled"
const TOAST_SECONDARY_REFILLED := "+%d rounds (%d)"

# ---- UI chrome ----

const OUTPOST_TITLE := "FRIENDLY OUTPOST"
const OUTPOST_COL_WEAPONS := "WEAPONS"
const OUTPOST_COL_UPGRADES := "UPGRADES"
const OUTPOST_COL_SERVICES := "SERVICES"
const OUTPOST_SELL_HEADER := "SELL EQUIPMENT"

const OUTPOST_STAT_HULL := "HULL"
const OUTPOST_STAT_SHIELD := "SHIELD"
const OUTPOST_STAT_PRIMARY := "PRIMARY"
const OUTPOST_STAT_SECONDARY := "SECONDARY"
const OUTPOST_STAT_SUPER := "SUPER"
const OUTPOST_STAT_BOUNTY := "BOUNTY"

# Empty-state labels.
const OUTPOST_WEAPONS_DEPLETED := "Stock depleted."
const OUTPOST_UPGRADES_MAXED := "All upgrades maxed."
const OUTPOST_STORAGE_EMPTY := "No spare equipment."

# Weapon-card button states.
const OUTPOST_BTN_EQUIPPED := "Equipped"
const OUTPOST_BTN_PURCHASED := "Purchased"
const OUTPOST_BTN_BUY := "Buy (%d)"
const OUTPOST_BTN_EQUIP := "Equip"
const OUTPOST_BTN_SELL := "Sell +%d"
const OUTPOST_BTN_LEAVE := "Leave"
const OUTPOST_BTN_REFRESH := "Refresh Stock (%d)"
const OUTPOST_BTN_REFRESH_MAX := "Refresh Stock (%d, max)"

# Slot short names (used in pill labels).
const SLOT_NAME_PRIMARY := "PRIMARY"
const SLOT_NAME_SECONDARY := "SECONDARY"
const SLOT_NAME_SUPER := "SUPER"
const SLOT_NAME_SHIELD := "SHIELD"
const SLOT_NAME_ENGINE := "ENGINE"
const SLOT_NAME_TAIL := "TAIL"
const SLOT_NAME_WING_L := "WING L"
const SLOT_NAME_WING_R := "WING R"
const SLOT_NAME_PART := "PART"

# Loadout line format strings.
const LOADOUT_PRIMARY := "PRI: %s"
const LOADOUT_SECONDARY := "SEC: %s"
const LOADOUT_SUPER := "SPR: %s"
