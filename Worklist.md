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
  bomber encounter). NOT STARTED.

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
- **EM Torpedo** — NOT STARTED (blocked-ish on wreck_layer, which it testbeds):
  When fired it sends out a large rocket (use the associated rocket projectile) that flies forward
  for two seconds then erupts into a burst of blue-yellow lightning that hits multiple enemies.
  Strips and ignores shields, and causes rockets/missiles to explode. Alternate kill effect:
  enemies have a 25% chance of exploding, and a 75% chance of becoming inert and drifting (with
  slight, randomized rotation) toward the bottom of the screen while trailing smoke (same smoke
  effect as the player, but respecting parent motion) — into the wreck_layer.

### Pulled / parked
- **Sector modifiers** — PULLED 2026-06-10 per Roman (kill-switch `Run.SECTOR_MODIFIERS_ENABLED =
  false` gates both rolling and application; vocabulary + effect wiring intentionally kept).
  **FLAGGED FOR RE-EVAL + REIMPLEMENT LATER.**
