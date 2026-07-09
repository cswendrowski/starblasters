extends Object

# DevData — read-only enumeration facade for the dev tools (docs/dev_tool_unification_design_2026-07-07.md).
#
# WHY: dev tools drift because each keeps a PRIVATE copy of an option table (movement keys, payload
# names, bullet inventory) that is a stale snapshot of a live production enumeration. This is a thin
# FACADE returning the *live* production vocabulary so no tool hardcodes it. It READS; it never writes.
#
# Preload-referenced, NOT a global class_name (headless-safe), mirroring scripts/levels/factions.gd.
# Every method is static and must be safe to call at editor/tool startup and in --headless boots.

const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")


# --- Movement keys (Phase 1) -----------------------------------------------------------------------
# The offerable movement keys for the eligibility / formation tools: the canonical SHAPE keys (owned by
# pattern_eligibility.gd, the production-adjacent home) PLUS the live authored-path keys ("path_<name>")
# merged from AuthoredPathLibrary (baked DATA + user:// overrides). Composing here is what makes a
# freshly authored path appear as an eligible/brushable movement in BOTH tools — solving Offender 1.
static func movement_keys() -> Array:
	var out: Array = PatternEligibility.MOVEMENT_KEYS.duplicate()
	# AuthoredPathLibrary has a global class_name; call it directly. movement_keys() reads the baked
	# library + (dev builds) the user:// override JSON, so a path authored mid-session shows up after
	# the caller triggers reload_overrides() on refresh.
	for k in AuthoredPathLibrary.movement_keys():
		if not out.has(k):
			out.append(k)
	return out


# The LIVE eligible movement set for an enemy scene: the canonical SHAPE keys AND eligible authored-path
# keys ("path_<name>") this enemy may be assigned, reflecting Roman's PENDING pattern_eligibility.json
# tuner save OVERLAID on the committed PatternEligibility.DATA — so an eligibility edit he Saved in the
# Pattern Eligibility tool shows up here (and in the Enemy Bench's read-only reflection) WITHOUT needing
# an Export/paste first. This is the one-directional authority chain's reflection point: the Pattern
# Eligibility editor is the ONLY place eligibility is SET; consumers (the bench) READ it live from here.
#
# Semantics mirror that editor's load precedence exactly (pattern_eligibility_editor._load_data): committed
# DATA first, then a saved per-scene record REPLACES the eligible list for that scene (not a union). Every
# key is canonicalized through the editor's KEY_REMAP + filtered to live keys (canonical shapes ∪ authored
# paths), and the identity is always folded into eligible (the editor's invariant). Read FRESH every call
# (no cache); a missing/malformed tuner file falls back to DATA silently. [] for a scene absent from the matrix.
static func eligibility_for(scene: String) -> Array:
	var live: Array = movement_keys()
	var identity: String = ""
	var eligible_raw: Array = []
	var committed: Variant = PatternEligibility.DATA.get(scene, null)
	if committed is Dictionary:
		identity = String((committed as Dictionary).get("identity", ""))
		var ce: Variant = (committed as Dictionary).get("eligible", [])
		if ce is Array:
			eligible_raw = (ce as Array).duplicate()
	# Overlay a PENDING saved edit for this scene (fresh read; malformed/missing → committed only).
	var parsed: Variant = _read_json(_ELIGIBILITY_OVERRIDE)
	if parsed is Dictionary and (parsed as Dictionary).has(scene):
		var rec: Variant = (parsed as Dictionary)[scene]
		if rec is Dictionary:
			var sid: String = _canon(String((rec as Dictionary).get("identity", "")), live)
			if sid != "":
				identity = sid
			var se: Variant = (rec as Dictionary).get("eligible", null)
			if se is Array:
				eligible_raw = (se as Array).duplicate()
	# Canonicalize + filter to live keys (collapse legacy → shape, drop retired), then ensure identity.
	var out: Array = _canon_list(eligible_raw, live)
	var cid: String = _canon(identity, live)
	if cid != "" and not out.has(cid):
		out.append(cid)
	return out


# Passthrough: all authored path names (baked + user-override, deduped).
static func paths() -> Array:
	return AuthoredPathLibrary.names()


# --- Bullet variants (Phase 2) ---------------------------------------------------------------------
# One live inventory of the enemy bullet .tres, scanned from data/bullets/ (the model is weapon_lab's
# existing dir-scan). Returns uniform {name, path} entries keyed on the NEW family vocabulary so the
# Enemy Bench and Weapon Lab present ONE vocabulary for the same physical bullets — solving Offender 2.
#
# Scope: TOP-LEVEL data/bullets/*.tres only. The 5 frame-reskin families (Ball/Bolt/Laser/Wave/Orb) plus
# the legacy Drop (drop_pellet.tres, still a distinct payload). Boss bullets live in data/bullets/boss/
# and are NOT enumerated here — neither the bench nor the weapon lab enemy-weapon dropdown offers them
# (they're wired directly on boss scripts), and folding them in would pollute the flat family dropdown.
const BULLET_DIR := "res://data/bullets/"

# Filename stem -> display/family name. Anything not listed falls back to a Title-cased stem so a NEW
# .tres dropped into data/bullets/ still appears (its family name derived from the file) — the whole
# point of scanning live. Order here also drives dropdown order for the known families.
const _BULLET_NAMES := {
	"ball": "Ball",
	"bolt": "Bolt",
	"laser": "Laser",
	"wave": "Wave",
	"orb": "Orb",
	"drop_pellet": "Drop",
}


static func bullet_variants() -> Array:
	var found: Dictionary = {}   # stem -> path
	var d := DirAccess.open(BULLET_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".tres"):
				found[f.get_basename()] = BULLET_DIR + f
	var out: Array = []
	# Emit the KNOWN families first, in declared order, so the dropdown is stable across machines.
	for stem in _BULLET_NAMES.keys():
		if found.has(stem):
			out.append({"name": String(_BULLET_NAMES[stem]), "path": String(found[stem])})
			found.erase(stem)
	# Then any NEW .tres not yet in the name table (Title-cased stem), sorted for determinism.
	var extra: Array = found.keys()
	extra.sort()
	for stem in extra:
		out.append({"name": _titleize(String(stem)), "path": String(found[stem])})
	return out


static func _titleize(stem: String) -> String:
	var parts: PackedStringArray = stem.split("_", false)
	var words: Array = []
	for p in parts:
		if p.length() > 0:
			words.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(PackedStringArray(words))


# --- Cross-tool pending-tune visibility (Phase 4, design §3.3 / RC5) --------------------------------
# READ-ONLY, PASSIVE surfacing of another tool's un-pasted user://tuners saves so a sibling tool can
# show a quiet "N pending in <other tool>" banner. This is a banner signal, NOT a data merge: NO tool
# writes another's file, and NO baked/user data is reconciled here. Each query re-reads the user:// file
# FRESH on every call (no caching — the answer must reflect the current on-disk state), and tolerates a
# missing/malformed/absent file SILENTLY by returning [] (a fresh install / headless boot has none).

const _PATHS_OVERRIDE := "user://tuners/enemy_paths.json"
const _ELIGIBILITY_OVERRIDE := "user://tuners/pattern_eligibility.json"
const PatternEligibilityEditor = preload("res://scripts/dev/pattern_eligibility_editor.gd")


# Path names present in user://tuners/enemy_paths.json (the Path Editor's Save target) that DIFFER from
# — or don't exist in — the baked AuthoredPathLibrary.DATA. A user entry that is byte-for-byte the baked
# default (same name + identical def) is NOT pending; a NEW name, or a same-named entry with any changed
# field, IS. This is exactly "authored paths the human hasn't pasted into the library yet" — the signal
# the Formation Builder + Eligibility Editor surface so Roman knows placed/eligible paths may not ship.
static func pending_paths() -> Array:
	var out: Array = []
	var entries: Variant = _read_json(_PATHS_OVERRIDE)
	if not (entries is Array):
		return out
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var nm: String = String((entry as Dictionary).get("name", ""))
		if nm == "":
			continue
		var baked: Variant = AuthoredPathLibrary.DATA.get(nm, null)
		# New name (not in DATA) OR a same-named entry whose definition differs = pending.
		if not (baked is Dictionary) or not _defs_equal(entry, baked):
			if not out.has(nm):
				out.append(nm)
	return out


# Scenes in user://tuners/pattern_eligibility.json whose entry DIFFERS from the committed
# PatternEligibility.DATA (a pending, un-exported eligibility edit). Mirrors the canonicalize+sort
# comparison the eligibility editor's _differs_from_baked uses: keys are collapsed through the editor's
# KEY_REMAP + filtered to LIVE movement keys (canonical shapes ∪ authored paths) so a pure legacy-key
# remap (which Export would bake identically) doesn't read as a spurious pending edit; identity + the
# sorted eligible set are then compared. A saved scene NOT in DATA counts as pending (a new authored
# entry the human hasn't exported). Read fresh, malformed/missing → [].
static func pending_eligibility() -> Array:
	var out: Array = []
	var parsed: Variant = _read_json(_ELIGIBILITY_OVERRIDE)
	if not (parsed is Dictionary):
		return out
	var live: Array = movement_keys()
	for scene in (parsed as Dictionary).keys():
		var rec: Variant = (parsed as Dictionary)[scene]
		if not (rec is Dictionary):
			continue
		var baked: Variant = PatternEligibility.DATA.get(scene, null)
		if not (baked is Dictionary):
			# Saved a scene the committed matrix doesn't ship → a pending new entry.
			if not out.has(String(scene)):
				out.append(String(scene))
			continue
		if _elig_differs(rec, baked, live):
			if not out.has(String(scene)):
				out.append(String(scene))
	return out


# True if two path-definition dicts are equal for pending purposes: same set of authoring fields with
# equal values. Compares the union of keys so an added/removed field also reads as a difference. Nested
# waypoint/dwell arrays compare structurally via ==.
static func _defs_equal(a: Dictionary, b: Dictionary) -> bool:
	var keys: Dictionary = {}
	for k in a.keys():
		keys[k] = true
	for k in b.keys():
		keys[k] = true
	for k in keys.keys():
		if a.get(k, null) != b.get(k, null):
			return false
	return true


# True if a saved eligibility record differs from the baked one (canonicalized + sorted), per the
# eligibility editor's _differs_from_baked semantics.
static func _elig_differs(rec: Dictionary, baked: Dictionary, live: Array) -> bool:
	if _canon(String(rec.get("identity", "")), live) != _canon(String(baked.get("identity", "")), live):
		return true
	var cur: Array = _canon_list(rec.get("eligible", []), live)
	var base: Array = _canon_list(baked.get("eligible", []), live)
	cur.sort()
	base.sort()
	return cur != base


# Collapse a possibly-legacy movement key through the eligibility editor's KEY_REMAP, then keep it only
# if it's a live key (canonical shape or authored path); "" otherwise. Static mirror of that editor's
# instance _canon so both sides of the pending comparison canonicalize identically.
static func _canon(key: String, live: Array) -> String:
	var k: String = String(PatternEligibilityEditor.KEY_REMAP.get(key, key))
	return k if live.has(k) else ""


static func _canon_list(keys: Array, live: Array) -> Array:
	var out: Array = []
	for k in keys:
		var c: String = _canon(String(k), live)
		if c != "" and not out.has(c):
			out.append(c)
	return out


# Read + JSON-parse a user:// file, returning the parsed Variant or null on any failure (absent file,
# unreadable, malformed JSON). Never throws, never writes.
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f.close()
	return JSON.parse_string(txt)
