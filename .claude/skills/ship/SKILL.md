---
name: ship
description: Verify a code change the right way and report it. Use after finishing any code edit — runs parse_check AND a headless scene boot (the step parse_check alone misses), then commits, pushes the working branch, and reports a summary to the user in the session. Invoke whenever work is "done" and needs to be verified + shipped to the working branch.
---

# /ship — verify-and-report loop

The discipline for finishing a change. **`parse_check` is necessary but NOT
sufficient** — it loads scenes but false-passes GDScript compile errors (a
`:=`-on-Variant error once shipped behind a green parse_check). The real verify
is a headless boot. Never skip step 3.

## Procedure

### 1. Scope the change
- `git status` + `git diff --stat` to see what changed.
- Map changed scripts → the scene(s) that load them. Combat-path scripts
  (player, director, enemies, waves, ui) → boot `scenes/main.tscn`. A specific
  enemy/effect → boot its own scene or `main.tscn`. Autoload/registry-wide
  changes → also do a full editor load (step 3b).

### 2. parse_check
```
tools/parse_check.ps1
```
Expect `All scenes parse-clean.` If it fails, fix before continuing.

### 3. Headless boot (the step that actually verifies compilation)
The Godot binary path lives in `tools/parse_check.ps1` (read it). Boot the
affected scene and grep for real errors:
```
& "<godot exe>" --path . --headless res://scenes/<scene>.tscn --quit-after 8
```
Grep the output for: `SCRIPT ERROR|Parse Error|Cannot infer|Failed to load`.
**Ignore these benign lines:** `custom_samplers`, `listen on port 9080`,
`another project.godot at res://addons/PixelPlanetsSource`, ObjectDB-leaked-at-exit.

**3b. Registry-wide / orphaned-script changes** — also run a full editor load,
which compiles the global class registry the way the editor does (catches
broken `preload()`s in orphaned `class_name` scripts that a scene boot misses):
```
& "<godot exe>" --path . --headless --editor --quit-after 20
```

If anything in YOUR change errors, fix and re-verify.

### 4. Visual change? Capture it.
If the change is visual, run the **/capture** skill to produce a GIF before
reporting, so the summary can point Roman at the result.

### 5. Commit (working branch)
- Stage the changed files **including any `.uid` sidecars** Godot generated
  (commit them; never hand-edit).
- Clear message; end the body with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Working-branch commits + pushes are fine without waiting. `git push origin <branch>`.
- **NEVER `butler push` / `tools/publish.ps1` here** — publishing to itch needs
  an explicit OK from the maintainer. That's the publish-gate path, not /ship.

### 6. Report to the user
Report the result directly in the session — no Discord, no external channels.
- A designer-level summary: what changed, the commit SHA, and crucially
  **what is verified (compiles + boots) vs. what is playtest-only** (wave feel,
  gameplay tuning, visual judgment can't be headless-verified — say so).
- Point at the GIF path if you captured one. Name any uncertainty.

## Notes
- See memory `feedback_verify_headless_boot` for why parse_check false-passes.
- See memory `feedback_git_push` for the push-vs-publish rule.
