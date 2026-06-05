class_name ScoreAdapter
extends RefCounted

# Lifts a flat LevelData (Array of WaveSpec) into a CombatScore (Wave -> Phrase).
#
# Shared producer-side score BUILDER (M5 native emission, 2026-06-04). Originally a
# transient director-side lift; now the producers own emission and call this:
# WaveGen.build_score(), the main.gd producer chokepoint (combat/boss/hazard/custom),
# and dev-tool LevelData paths. The conductor performs the CombatScore via start_score
# and no longer lifts LevelData itself on the production path (director.start_level is
# now just a compat shim for LevelData-holding callers). Kept (not deleted) because a
# single LevelData->CombatScore builder is the DRY home for this assembly; M6's native
# phrase authoring (walls/filler/faction/telegraph) grows in WaveGen.build_score on top.
#
# Faithful, lossless lift: each WaveSpec becomes one FORMATION phrase wrapping
# that spec (so director._spawn_enemy still materializes it identically); the
# `silent` flag groups sub-waves under one ScoreWave, mirroring the director's
# silent-chaining (director.gd:82). Legacy Formation enum -> a shape id the
# conductor maps back to placement.

static func from_level_data(level: Resource) -> CombatScore:
	var score := CombatScore.new()
	if level == null:
		return score
	if "level_name" in level:
		score.level_name = level.level_name
	var waves: Array = (level.waves if "waves" in level else [])
	var current: ScoreWave = null
	var wave_count: int = 0
	for spec in waves:
		if spec == null:
			continue
		var is_silent: bool = ("silent" in spec) and spec.silent
		# A non-silent wave (or the very first wave) opens a new ScoreWave;
		# silent sub-waves attach as further phrases of the current one.
		if current == null or not is_silent:
			# Pacing: close the previous wave with a breather every Nth wave so a
			# high-volume level rises and releases instead of one unbroken stream.
			# (Interim in the adapter; WaveGen v2 will author breathers natively.)
			if current != null and wave_count % BREATHER_EVERY == 0:
				current.phrases.append(_breather())
			current = ScoreWave.new()
			current.banner = (spec.announce_text if "announce_text" in spec else "")
			score.waves.append(current)
			wave_count += 1
		var ph := Phrase.new()
		ph.kind = Phrase.Kind.FORMATION
		ph.specs = [spec]
		ph.shape = _shape_id(spec)
		ph.entry = (&"side" if _is_side(spec) else &"top")
		current.phrases.append(ph)
	return score


# Insert a breather after every Nth wave (pacing — see from_level_data).
const BREATHER_EVERY: int = 2


static func _breather() -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.BREATHER
	ph.duration = 2.0       # max exhale
	ph.alive_floor = 5      # ...or end early once the screen drains to this
	return ph


static func _is_side(spec: Resource) -> bool:
	return ("formation" in spec) and int(spec.formation) == 4  # SIDE_ALTERNATING


static func _shape_id(spec: Resource) -> StringName:
	if not ("formation" in spec):
		return &"top_spread"
	match int(spec.formation):
		0: return &"left_to_right"
		1: return &"right_to_left"
		2: return &"random"
		3: return &"center_out"
		4: return &"side_alternating"
		5: return &"tandem_pairs"
		6: return &"wall"
		7: return &"pincer"
		_: return &"top_spread"
