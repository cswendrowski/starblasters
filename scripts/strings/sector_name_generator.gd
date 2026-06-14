extends RefCounted
class_name SectorNameGenerator

# Deterministic sci-fi sector name generator. Same seed always produces the
# same name so reloads / map re-entries don't shuffle the header text.
#
# Public API:
#   SectorNameGenerator.generate(seed_value: int) -> String
#
# Style mix: real astronomical designations (catalog IDs + named stars) plus
# softer sci-fi flavor (Greek + number, "Outer X", "Beacon-X", etc). Tuned to
# read as a plausible patrol beat name without slipping into obvious fantasy.


# --- Name part pools ---------------------------------------------------------
# Designer-tunable. Keep each pool short enough that repeats are unlikely
# inside a 3-sector run.

const GREEK := [
	"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
	"Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
	"Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega",
]

# Real(ish) star + system names — the workhorse of the realistic side.
const REALISTIC_STARS := [
	"Tau Ceti", "Wolf 359", "Barnard", "Proxima", "Vega", "Altair", "Rigel",
	"Antares", "Procyon", "Aldebaran", "Capella", "Sirius", "Arcturus",
	"Betelgeuse", "Polaris", "Mira", "Deneb", "Spica", "Regulus", "Bellatrix",
	"Castor", "Pollux", "Fomalhaut", "Achernar", "Canopus", "Lacaille",
	"Ross 128", "Gliese 581", "Luyten", "Kapteyn",
]

# Catalog-style prefixes for "<DESIG>-<NUM>".
const DESIGNATIONS := [
	"NGC", "IC", "HD", "HR", "M", "Cygnus", "Kepler", "TRAPPIST", "PSR",
	"Sigma-Dra", "Eta-Car", "Wolf", "Gliese", "HIP",
]

# Sci-fi flavor prefixes — combined with a realistic star or number.
const SF_PREFIXES := [
	"Reach", "Outpost", "Beacon", "Drift", "Verge", "Outer", "Inner",
	"Bastion", "Frontier", "Halo", "Rim", "Spire", "Vault", "Forge",
]

# Adjectives for "<Adjective> <Realistic>".
const ADJECTIVES := [
	"Outer", "Inner", "Lost", "Quiet", "Broken", "Forgotten", "Distant",
	"Pale", "Hollow", "Twin", "Far", "Deep",
]

# Suffixes for the Greek-style names. "Alpha-Prime", "Beta-7", etc.
const GREEK_SUFFIXES := [
	"Prime", "Secundus", "Tertius", "Minor", "Major", "Reach", "Drift",
]

# Numeric tokens — written out a few times to break up the "always digits"
# feel.
const NUMBER_WORDS := [
	"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
]


# --- Templates ---------------------------------------------------------------
# Each template is a numeric tag the picker rolls into. Weights below.

const TEMPLATES := [
	"GREEK_NUM",         # "Alpha 7" / "Tau-12"
	"GREEK_SUFFIX",      # "Beta Prime", "Delta Reach"
	"REALISTIC",         # "Tau Ceti"
	"DESIGNATION_NUM",   # "NGC-1142"
	"ADJ_REALISTIC",     # "Outer Procyon"
	"SF_PREFIX_NUM",     # "Reach-7"
	"SF_PREFIX_STAR",    # "Beacon-Vega"
	"GREEK_NUMWORD",     # "Sigma-Seven"
]

# Weights — favor realistic + designation styles so the bulk reads grounded,
# Greek/SF flavor for variety.
const TEMPLATE_WEIGHTS := [
	2,  # GREEK_NUM
	1,  # GREEK_SUFFIX
	4,  # REALISTIC
	3,  # DESIGNATION_NUM
	2,  # ADJ_REALISTIC
	2,  # SF_PREFIX_NUM
	2,  # SF_PREFIX_STAR
	1,  # GREEK_NUMWORD
]


static func generate(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tmpl: String = _weighted_pick(rng, TEMPLATES, TEMPLATE_WEIGHTS)
	match tmpl:
		"GREEK_NUM":
			var sep := "-" if rng.randi() % 2 == 0 else " "
			return "%s%s%d" % [_pick(rng, GREEK), sep, rng.randi_range(1, 19)]
		"GREEK_SUFFIX":
			return "%s %s" % [_pick(rng, GREEK), _pick(rng, GREEK_SUFFIXES)]
		"REALISTIC":
			return _pick(rng, REALISTIC_STARS)
		"DESIGNATION_NUM":
			return "%s-%d" % [_pick(rng, DESIGNATIONS), rng.randi_range(7, 9999)]
		"ADJ_REALISTIC":
			return "%s %s" % [_pick(rng, ADJECTIVES), _pick(rng, REALISTIC_STARS)]
		"SF_PREFIX_NUM":
			return "%s-%d" % [_pick(rng, SF_PREFIXES), rng.randi_range(1, 49)]
		"SF_PREFIX_STAR":
			return "%s-%s" % [_pick(rng, SF_PREFIXES), _pick(rng, REALISTIC_STARS)]
		"GREEK_NUMWORD":
			return "%s-%s" % [_pick(rng, GREEK), _pick(rng, NUMBER_WORDS)]
	# Shouldn't happen — templates exhausted above. Fall back to a realistic
	# star rather than empty string so the header always has text.
	return _pick(rng, REALISTIC_STARS)


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return arr[rng.randi() % arr.size()]


static func _weighted_pick(rng: RandomNumberGenerator, arr: Array, weights: Array) -> String:
	var total: int = 0
	for w in weights:
		total += int(w)
	var roll: int = rng.randi() % total
	var acc: int = 0
	for i in arr.size():
		acc += int(weights[i])
		if roll < acc:
			return String(arr[i])
	return String(arr[arr.size() - 1])
