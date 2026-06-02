# Godot + Claude: Learnings for a New Project

Portable notes from working on a Godot 4 project as an AI agent, for a *future
Claude instance starting a different Godot project* — possibly 3D, possibly not
a game. Ordered by leverage. The 2D/pixel-art-only bits are fenced at the end so
they don't mislead a 3D project.

---

## 1. Verification: the single highest-leverage discipline

**A scene/asset "parse check" or load check FALSE-PASSES GDScript compile
errors.** Loading a scene resource is not the same as compiling every script the
running game uses. You can have a green parse check and a hard crash on play.

- **Always boot headless and grep the output** before claiming a code change
  works: `godot --path . --headless res://path/to/scene.tscn --quit-after 8`,
  then look for `SCRIPT ERROR | Parse Error | Cannot infer | Failed to load`.
- **For class-registry / orphaned-script problems, do a full editor load:**
  `godot --path . --headless --editor --quit-after 20`. A `class_name` script
  that no scene references (dead code with a broken `preload()`) won't be
  compiled by a scene boot — only a full project load (or web export) compiles
  the global class registry. ~20s lets the filesystem scan finish; 5s aborts it.
- **Ignore the benign noise** in headless output (shader sampler warnings, addon
  WebSocket "failed to listen on port", duplicate-project warnings from nested
  addons, "ObjectDB leaked at exit"). Judge on the real error patterns, not the
  process exit code — exit codes are unreliable when an editor instance is
  already running.
- When reporting to a human, **separate "verified (compiles + boots)" from
  "behaviour I could not headless-verify"** (game feel, timing, visuals). Don't
  imply you tested what you couldn't.

**`:=` (inferred typing) on a Variant value is a HARD COMPILE ERROR, not a
warning.** `var x := some_untyped_call()` / `get_node_or_null(...)` /
`untyped_array[i]` → "Cannot infer the type of X". A blanket
`var x =` → `var x :=` cleanup *will* break the build in spots a parse check
misses. Only use `:=` when the RHS type is statically known; otherwise leave
`var x = …` (a benign warning) or write `var x: Type = …`.

Set up a fast verification command early and *actually run it* — don't trust a
green light from a tool that doesn't compile scripts the way play does.

---

## 2. Godot engine gotchas (apply to 2D and 3D)

- **Base classes hard-reference child nodes by name** (`$Sprite2D`,
  `$MeshInstance3D`, `$AnimationPlayer`). Renaming a child silently breaks the
  parent's `_ready`/`_process`. Before renaming any node, grep for `$Name` /
  `get_node("Name")` / `"Name"`. When building a scene to fit a base class, keep
  the expected child names.
- **Set exported/stat values BEFORE `super._ready()`** if the base reads them in
  `_ready()` (e.g. to size a health bar). Initializing after, or via a lazy
  `value <= 0 ? default` pattern, causes subtle "it's using the default" bugs.
- **Resources and Materials are shared by reference across instances.** A scene
  with an inline `[sub_resource]` material shares ONE material across every
  instance — `material.set_shader_parameter(...)` is last-write-wins for all of
  them. `.duplicate()` the material per instance before setting per-instance
  params. Same principle for any `Resource` used as a behaviour slot: **keep
  per-instance mutable state on the NODE, not on the shared Resource** (two
  enemies sharing a "pattern" Resource must not store their cursor on it).
- **`.uid` sidecar files are Godot-generated — commit them, never hand-edit.**
  New scripts/scenes need their `.uid` for stable references; reference
  resources by `uid://… + path`. Imported textures store their uid *inside* the
  `.import` file (no separate `.uid` for them) — after dropping a new asset, run
  a headless `--import` pass to generate the `.import`/`.ctex` sidecars, then
  commit them. Missing sidecars can pass locally and fail on export.
- **Runtime `DirAccess` scans of `res://` return EMPTY in exported builds**
  (especially web). Never enumerate `res://` directories at runtime to discover
  content — use an explicit hardcoded manifest / preload list.
- **Lifetime ownership of spawned nodes.** Anything that must outlive its spawner
  (projectiles, detached effects, pooled objects) must be parented to a
  persistent node (the scene root or a dedicated container), NOT the emitter —
  the emitter's `queue_free()` takes its children with it.
- **Signals:** guard reconnections (`if not sig.is_connected(cb): sig.connect(cb)`)
  so re-entering a scene doesn't double-fire; disconnect/free on teardown. A
  duplicate connection is a silent double-execution bug.
- **Determinism / RNG:** seed from a single run/world seed for reproducibility.
  Dev tools and test scenes usually run WITHOUT your autoloads — if procgen
  falls back to a *constant* seed when the seed-source autoload is absent, every
  "regenerate" looks identical and the generator seems broken. Fall back to a
  time-based seed in tool context, keep the deterministic seed in-game.

---

## 3. Architecture patterns that paid off

- **Autoloads (singletons) for state that must survive scene changes** — run
  state, settings, audio context, debug helpers. Keep each focused on one thing.
- **Prefer data-driven composition over deep inheritance.** Model entity
  behaviour as pluggable `Resource` slots (a "movement" resource, a "behaviour"
  resource) on a thin core node, rather than a bespoke script per entity.
  Reserve bespoke scripts for behaviour a slot genuinely can't express
  (multi-phase state machines, continuous effects). This keeps the common case
  cheap and the registry of behaviours reusable. Check for an existing
  slot/resource before writing new per-entity logic.
- **Scene-driven content + a registry.** Define content (enemies, items, levels)
  as scenes referenced from a data table/registry with their spawn/gating rules,
  not hardcoded `if`-ladders. New content = a scene + a registry row.
- **Search before you build.** A "new" mechanic the human asks for may already
  exist in the codebase under a different name. Grep the relevant subsystem for
  the concept (`shield`, `summon`, `phase`, `pool`…) before designing it from
  scratch or asking the human to spec it — you may just need to wire new
  art/data into an existing system.
- Files that change together live together; keep scripts focused enough to hold
  in context.

---

## 4. Working with a human maintainer (game/visual projects especially)

- **Context is the scarce resource. Iteration-heavy tuning belongs in a tool the
  human runs, not an agent edit-run-look loop.** For any system with ~3+ knobs
  (layout, visual, numeric balance), scaffold a *tuner* scene with live controls
  and a "copy the values" export button; have the human iterate and paste back
  the result. Don't burn turns capturing-and-eyeballing what a slider would do.
- **For visual changes, produce an artifact (screenshot/GIF) and show the human
  — don't read raw frames.** Write a one-shot capture script per mechanic, pipe
  to a GIF, and self-review the GIF once before declaring done (capture warm-up
  frames are often blank — check a mid-action frame). Name your visual
  uncertainty instead of asserting it's perfect.
- **Project-instruction files (CLAUDE.md) should hold RULES, and POINT to
  volatile FACTS.** They load into context every session, so a *stale fact*
  (exact filename, threshold, key binding, tool list) actively misleads you.
  Keep load-bearing invariants + stable orientation inline; for anything that
  drifts, link the code/doc that owns it. "Rule vs fact" is the test: an
  instruction that stays valid as code moves → keep; a value that describes
  current state → point at its source.
- **Comment as you go, two layers:** the non-obvious (gotchas, invariants,
  why-this-not-that) and a plain-language "what this block does and why" pitched
  at someone new to the engine. Never restate the code. Avoid giant separate
  comment passes — they're low-signal and rot.
- **Don't ship placeholder art/data into a production path unilaterally.** Before
  publishing, grep the live content registry for placeholder content; publishing
  drops it in front of every user. Hold or pull, and let the maintainer decide.
- **Reversibility decides "ask vs build."** For a cheap, reversible change
  (a value, a visual pass), build a first version and flag it for the human to
  react to. For an expensive, low-reversibility decision (a bespoke state machine
  touching shared/fragile code, ~6 coupled design unknowns), ask ONE tight,
  optioned question bundled with the progress you already shipped — don't guess.
- **Publishing/releasing is a gated, human-confirmed action.** Routine commits
  and working-branch pushes are fine; a real release (store push, deploy) needs
  explicit sign-off every time. Keep a pre-flight checklist (right binary, fresh
  build, version bump, no dev cruft bundled).

---

## 5. Delegation / agent hygiene (if you have subagents)

- Delegate multi-file or exploratory work to subagents and keep the *conclusion*,
  not the file dumps — protects your own context budget.
- Give read-only exploration to a search agent; have it return `file:line`
  citations, not raw dumps.
- Run independent edits on **disjoint files** in parallel; never parallel-edit
  the same file. Have subagents NOT commit — do a single combined verification
  and commit yourself so you control the history and catch cross-edit breakage.
- **Accuracy outranks completeness for docs/onboarding** — a confident wrong fact
  propagates to everyone. Have authors verify against real code with citations,
  and do one assembly read for contradictions.

---

## 6. 2D / pixel-art specific (SKIP if your project is 3D or non-pixel)

- `rendering/textures/canvas_textures/default_texture_filter = 0` (nearest) for
  crisp pixel art; `2d/snap/snap_2d_transforms_to_pixel` to avoid shimmer.
- Sprite sheets via `hframes`/`vframes`; **a shader on a multi-frame sprite
  samples the whole sheet** — any neighbor-sampling effect (bloom, blur,
  outline) will bleed adjacent frames into the result unless it's constrained to
  the current frame's UV sub-rect. Fix by passing the frame rect to the shader,
  or by feeding the effect a single extracted frame.
- Decide your coordinate space deliberately: an internal low-res viewport scaled
  up (e.g. via `SubViewportContainer` with `stretch_shrink`, nearest filter) vs
  native. `CanvasLayer` nodes ignore the 2D transform hierarchy and render in
  viewport space — you can't scale them by scaling a parent; use the viewport /
  a SubViewport. `Control` anchors only resolve against a `Control` parent (a
  `Control` under a `Node2D` gets size 0 — set size/offsets explicitly).
- Keep backdrop/parallax `CanvasLayer`s at negative layer indices so UI (layer
  0+) renders above them.

---

*These are starting heuristics, not law — verify each against your project's
engine version and conventions. The meta-lesson: in Godot, the failure modes are
usually "it loaded but didn't compile," "the resource was shared," "the node name
was hard-coded," and "the asset sidecar was missing" — check those first.*
