extends RefCounted

# FiringScheduler (roadmap P3.9 — 2026-07-02): the ONE trigger-resolution engine shared by the
# hull weapon (enemy_core) and the mount weapons (mount_component). Before this, the path-phase
# line-crossing + beat-sync quantize (with the fast-mover departure escape) + the shared fire gates
# lived in TWO near-identical copies that drifted (see docs/conductor_systems_review_2026-07-02.md
# §3 "Firing"). This class owns the trigger DECISIONS; each host keeps its own tick source (the
# hull's ShootTimer node, the mount's on_process accumulator) and its own bullet-spawn path.
#
# One instance per emitter (RefCounted, not a Node — no tree plumbing). The hull constructs one;
# each MountComponent constructs one. State (`_phase_idx`, `_beat_fire_at`) is per-emitter so two
# guns on the same enemy schedule independently.
#
# HOST CONTRACT — duck-typed, works with BOTH host shapes:
#   * enemy_core (full):  has _dying / _cycling / _last_move_vel / _on_playfield() / find_player().
#   * pure enemy_base (bombers, bulwark, mount hosts): has _dying / _cycling / _last_move_vel but
#     may lack _on_playfield(); we fall back to an inline off-screen box there (mirrors the old
#     mount code). Every field we read is probed with `in` / has_method exactly as the old copies did.
#
# Preload-const, NOT class_name (the firing-resource convention — a fresh class_name doesn't resolve
# under headless --script until the cache regenerates; mount_component/weapon do the same).

const Zones := preload("res://scripts/systems/zones.gd")
const Beat := preload("res://scripts/systems/beat.gd")

# Path-phase firing (construction §8): fractions [0,1] of engagement-band progress at which to fire.
# Firing-consistency pass (2026-07-02): first phase near the TOP of the band (0.1 -> ~y63, "fires
# promptly on entering") and the second at mid-band (0.5 -> ~y118), both kept clear of the
# DEPARTURE_START (195) edge so no shot lands in the departure/cease-fire band. The old [0.35, 0.75]
# held fire for the first third (read as "fires late") and put the 2nd shot at the departure edge.
# Keep ascending + <=0.6. (Owned here as the single source; enemy_core auto-populates from it, the
# mount deliberately does NOT — see the auto_populate_default flag below.)
const DEFAULT_PATH_PHASES := [0.1, 0.5]

# Path-phase state (per-emitter). _phase_idx = next band-progress line to cross; _beat_fire_at =
# engine-clock time a pending beat-synced shot fires (-1 = none).
var _phase_idx: int = 0
var _beat_fire_at: float = -1.0


# Reset the path-phase cursor for a fresh descent (spawn or recycle re-arm). The hull calls this
# from _start_with_pattern / _recycle_resume; the mount has no recycle (enemy_core-only) but resets
# _phase_idx implicitly on construction.
func reset() -> void:
	_phase_idx = 0
	_beat_fire_at = -1.0


# --- Path-phase firing --------------------------------------------------------------------------
# Called each movement frame. Fires one shot each time the host descends past the next configured
# band-progress fraction, so shots land at fixed screen positions during the pass (telegraph-friendly,
# never "too late") and a descending formation volleys together at the same Y line. Phases must be
# ascending; max phase < 1.0 means firing naturally ceases before the departure band.
#
# `phases`      — ascending band-progress fractions (PackedFloat32Array).
# `beat_synced` — quantize each shot to the shared Beat tempo (cross-formation volley collapse).
# `fire_gated`  — Callable(): performs the ACTUAL shot, re-checking the live guards itself (the
#                 beat-synced path defers the shot, so the host may have started dying / left the
#                 band by the time it fires). Both hosts pass a callable wrapping their _do_path_shot.
func tick_path_phases(host, phases: PackedFloat32Array, beat_synced: bool, fire_gated: Callable) -> void:
	# 1) Release a pending beat-synced shot once its global beat arrives. Checked first +
	# unconditionally so the last queued shot still fires after the final phase line is crossed
	# (idx exhausted).
	if _beat_fire_at >= 0.0 and Beat.now() >= _beat_fire_at:
		_beat_fire_at = -1.0
		fire_gated.call()
	# 2) Detect crossing the next phase line.
	if phases.is_empty() or _phase_idx >= phases.size():
		return
	# Hard stops before evaluating a crossing. _dying/_cycling are duck-typed so a pure enemy_base
	# host (bomber) is guarded too — the old mount copy relied on upstream _tick_components gating
	# and skipped this, unified here to the SAFE behavior (review §6 first bullet).
	if _is_dying(host) or _is_cycling(host) or not _on_playfield(host):
		return
	if Zones.band_progress(host.position.y) < phases[_phase_idx]:
		return
	_phase_idx += 1
	if beat_synced:
		# Quantize to the shared tempo so cross-formation shots collapse into a volley — BUT only
		# when the host will still be inside the engagement band when that beat lands. Fast movers
		# (Hot Rods at 300 px/s) cross the whole 155px band in ~0.5s, less than the 0.45s beat
		# period, so a deferred shot would fire in (or past) the departure band — fire NOW instead
		# so the shot lands in-zone. Slow waves still get their beat-synced volley. (Roman
		# 2026-06-14: "fire properly in the zones even when moving fast".)
		var beat_at: float = Beat.next_beat_time(Beat.now())
		var vel_y: float = _vel_y(host)
		var predicted_y: float = host.position.y + vel_y * maxf(0.0, beat_at - Beat.now())
		if predicted_y >= Zones.DEPARTURE_START:
			fire_gated.call()
		else:
			_beat_fire_at = beat_at
	else:
		fire_gated.call()


# --- Shared fire gates --------------------------------------------------------------------------
# Zone / nose gates shared by the cadence + path-phase + phase-event fire paths. Holds fire outside
# the engagement band (fire_zone_gated) or until the nose lines up (fire_only_on_target). Mirrors
# the guard block enemy_core._on_shoot_timer_timeout and mount_component._gates_pass both ran.
func gates_pass(host, zone_gated: bool, only_on_target: bool, aim_tol_deg: float) -> bool:
	if zone_gated and not Zones.in_engagement(host.position.y):
		return false
	if only_on_target and not nose_on_player(host, aim_tol_deg):
		return false
	return true


# --- Nose-cone alignment ------------------------------------------------------------------------
# True when the host's forward vector is within `aim_tol_deg` of the direction toward the player.
# Sprite faces +Y at rotation 0 → forward derived from rotation - PI/2. Mirrors the omni/inertial/jet
# facing math. Duck-typed find_player so a host without it simply never aligns.
static func nose_on_player(host, aim_tol_deg: float) -> bool:
	var player = host.find_player() if host.has_method("find_player") else null
	if player == null:
		return false
	var to_p: Vector2 = player.global_position - host.global_position
	if to_p.length_squared() < 1.0:
		return false
	var rot: float = host.rotation - PI * 0.5
	var fwd: Vector2 = Vector2(cos(rot), sin(rot))
	return fwd.dot(to_p.normalized()) >= cos(deg_to_rad(aim_tol_deg))


# --- Host duck-typing helpers -------------------------------------------------------------------
# _dying/_cycling live on enemy_base so every real host has them; probe with `in` so a stray
# non-enemy host can't crash the scheduler.
static func _is_dying(host) -> bool:
	return "_dying" in host and host._dying


static func _is_cycling(host) -> bool:
	return "_cycling" in host and host._cycling


# Applied-velocity Y for the beat-sync departure prediction. Duck-typed on _last_move_vel: if the
# host never tracked motion, treat it as stationary (0).
static func _vel_y(host) -> float:
	return host._last_move_vel.y if "_last_move_vel" in host else 0.0


# "On the visible playfield" check. enemy_core provides the strict _on_playfield() (8px margin,
# playfield-band X); pure enemy_base hosts (bombers, bulwark, mount hosts) don't, so fall back to an
# inline 8px-margin viewport box there — EVERY host holds fire while well off-screen (Roman
# 2026-06-29). X uses the full viewport so the gutters never gate; only the Y edges suppress fire.
static func _on_playfield(host) -> bool:
	if host.has_method("_on_playfield"):
		return host._on_playfield()
	if not (host is Node2D):
		return true
	const M := 8.0
	var sz: Vector2 = host.get_viewport_rect().size
	var p: Vector2 = host.position
	return p.x >= M and p.x <= sz.x - M and p.y >= M and p.y <= sz.y - M
