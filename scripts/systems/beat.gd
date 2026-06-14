class_name Beat
extends Object

# Global firing tempo (bridge glossary "Beat"): ONE shared clock so conducted enemies
# across DIFFERENT formations volley on the same rhythm instead of each firing on its
# own timer/phase. Path-phase firing (enemy_core) quantizes each shot to the next beat
# via next_beat_time(), so concurrent "ready to fire" across the screen collapses onto
# one tick and reads as a volley. (Within-formation sync already comes for free from
# band-Y path progress; this adds the cross-formation layer.)
#
# Pure function of the engine clock — every enemy reads the same beat with no node or
# reference, like Zones/Lanes/Playfield. TEMPO ONLY — never a composition unit (that's
# Phrase). PERIOD is the single tuning knob (shorter = tighter volleys + less per-shot
# latency; longer = more pronounced rhythm but shots lag their phase line more).

const PERIOD: float = 0.45  # seconds per beat (~133 BPM). The shared-volley knob.


# Seconds since engine start — the shared time base every enemy reads.
static func now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# The next beat boundary strictly after t (seconds). A shot made "ready" at t fires
# here, so readiness across formations collapses onto one tick. Always in (t, t+PERIOD].
static func next_beat_time(t: float) -> float:
	return (floor(t / PERIOD) + 1.0) * PERIOD


# Beat index at time t — for telegraphs / future formation timing on the same grid.
static func index(t: float) -> int:
	return int(floor(t / PERIOD))
