extends Object

# Codex flavor strings — FACTION display names + faction/Starblaster codex entries.
# Faction display names are authoritative; the codex bodies are PLACEHOLDERS for
# Roman/Cody to fill in (the codex pulls these verbatim). Per-enemy names + blurbs
# live in enemy_strings.gd, not here.
#
# Preload-referenced, NOT a class_name (headless class-cache safety, matching
# enemy_strings / factions). Usage:
#   const CodexStrings = preload("res://scripts/codex_strings.gd")
#   CodexStrings.faction_name("supremacy")   CodexStrings.faction_codex("supremacy")
#   CodexStrings.STARBLASTER["name"] / ["codex"]

# Keyed by Factions.id_key(id): "supremacy" / "privateer" / "corporate" / "zealot".
const FACTIONS := {
	"supremacy": {
		"name": "Crimson Supremacy",
		"codex": "[PLACEHOLDER — faction codex entry. The Crimson Supremacy: aggressive, fast-firing. Fill me in.]",
	},
	"privateer": {
		"name": "Vertarine Armada",
		"codex": "[PLACEHOLDER — faction codex entry. The Vertarine Armada: tough hulls, mixed crews; they sprinkle into anyone's space. Fill me in.]",
	},
	"corporate": {
		"name": "UltraGalactic Concerns",
		"codex": "[PLACEHOLDER — faction codex entry. UltraGalactic Concerns: shielded, methodical, corporate enforcement. Fill me in.]",
	},
	"zealot": {
		"name": "Evantian Theocracy",
		"codex": "[PLACEHOLDER — faction codex entry. The Evantian Theocracy: zealots who scatter firecore in their wake. Fill me in.]",
	},
}

# The player's ship — a placeholder entry shown alongside the factions.
const STARBLASTER := {
	"name": "Starblaster",
	"codex": "[PLACEHOLDER — the Starblaster. Your ship. Codex entry for Roman to fill in.]",
}


static func faction_name(key: String) -> String:
	var e: Variant = FACTIONS.get(key, null)
	if e != null:
		return str(e.get("name", key))
	return key


static func faction_codex(key: String) -> String:
	var e: Variant = FACTIONS.get(key, null)
	if e != null:
		return str(e.get("codex", "TBD"))
	return "TBD"
