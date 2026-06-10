# Worklist — remaining items (cleaned 2026-06-10)

The 2026-06-10 batch completed most of the original list — full per-item log, commits, and the
**Needs-Roman eyeball checklist** live in `Worklog.md`. Done + verified: all Outpost UX (7 items),
all Audio (incl. distance-based explosions), all Music ramping (incl. permanent per-boss step), all
HUD items, Phase + Hyper modes, Minigun + Autocannon (Machinegun retired), Rotary Mk5+ projectile
swap, enemy-cannon animation fix, zealot ball-explosion routing, Enemy-Bench recycle tagging,
Manage-Ship shift modes, onboarding refresh, Omni no-fly fix, off-screen-enemy hit immunity —
plus the playtest hotfixes (primary fire, old death-sound retirement, firecores, outpost dupes).

What's actually left:

### Core — ON HOLD (attended-session decision)
Go to Forward+ renderer + Windows-only build as the new itch publishing setup. HELD 2026-06-10:
re-bases all visual work and can't be validated headless — schedule as its own attended block
(ideally the FIRST thing of a session so everything after is tested under the new renderer).

### Play Area
- **Pillar 2 Recycler** — central RecycleController + RecycleTuner dev scene; merge the missile
  cruiser's bespoke version; migrate the roster onto it. NOT STARTED. Build order + full handoff in
  `Worklog.md` (spec: `docs/recycling_system_pillar2_2026-06-04.md`; TODO.md "Recycling — Pillar 2").
  Prereq tooling (Enemy-Bench recycle/flee tagging) landed 2026-06-10. Regression surface = the whole
  roster → wants live playtest during the migration.
- **wreck_layer** — near-parallax-depth layer enemies "fall" into on death; same color grading as
  the near layer. EM Torpedo is the testbed; if it reads well, expand to more death styles (e.g. the
  bomber encounter). **BUILT 2026-06-10 (`9d99405`, test-gated)** — world-space layer graded to the
  near band; enemies route into it via a generic `death_style="wreck"` intercept in
  `enemy_base.explode()`, so wiring the bomber encounter later is just tagging those kills. NEEDS
  EYEBALL (see Worklog).

### Patterns
- **Lane Hook is not leaving the play area properly.** NEEDS REPRO — the code-side exit config
  verified correct (DIVE_RETURN shape, frees on any edge after the U-turn climb), so I need the
  in-game symptom: stalls mid-climb? exits the wrong edge? recycles instead of leaving?

### Enemies
- **Supremacy Push globbing** — controlled numbers, one to a lane / one per crossing. NEEDS STEER —
  the fix lives in shared director placement code (lane-spread + crosser stagger exist but the push
  anchors bypass them); confirm whether it's the descenders stacking or the side_traverse crossers
  overlapping, and I'll route just those through the right spread.

### DEV
- **Hangar rebuild** — muzzle flashes colored green, bullets missing. Deep dive on the SubViewport
  and rebuild it so the live-fire bench works. NOT STARTED (prior parent-routing fix insufficient).

### New Secondary Weapons
- **EM Torpedo** — **BUILT 2026-06-10 (`9d99405`, test-gated, NOT in shop pool)**. Large dumb-fire
  rocket → blue-yellow chain-lightning burst; strips/ignores shields, chain-detonates enemy
  ordnance, 25% explode / 75% wreck-drift kills. Behind Test Combat → "EM Torpedo + Wreck Test"
  (fire with C). Deltas from the original spec, flagged for Roman's call: (a) bursts at the TOP of
  the play band (detonate_y) rather than a literal 2s forward flight — the 270px field is too short
  for 2s of travel; fuse=2.0 is a backstop. (b) Wreck smoke uses MissileSmokeTrail (the world-space
  "copy of the player damage-smoke"); swap to the darker DamageSmokeTrail palette if you want it to
  match the player's exactly. To promote to live: add `_make_em_torpedo` to `part_catalog._all_pool`
  + author `resources/weapons/em_torpedo.tres`. NEEDS EYEBALL/feel pass (see Worklog).

### Pulled / parked
- **Sector modifiers** — PULLED 2026-06-10 per Roman (kill-switch `Run.SECTOR_MODIFIERS_ENABLED =
  false` gates both rolling and application; vocabulary + effect wiring intentionally kept).
  **FLAGGED FOR RE-EVAL + REIMPLEMENT LATER.**
