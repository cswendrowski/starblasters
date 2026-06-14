# 01 · Getting Started & the Contribution Loop

Welcome. This doc walks you through **engine setup**, **how to run the project**, **how to verify your changes**, and **the workflow for committing and pushing**. We'll keep it concrete — actual commands, actual paths, actual limitations.

---

## Engine & project setup

### Godot 4.6.3 standalone

Starblaster runs on **Godot 4.6.3 standalone** — the single binary that serves as both editor and web exporter. There is no C#/Mono (the project never used C#, and the split Mono editor + 4.4.1 exporter was consolidated on 2026-05-26).

The binary lives at:
```
C:\Users\Cody\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe
```

If you're setting up a fresh machine or the binary moves, update it in **both** of these files:
- `tools/parse_check.ps1` (line 2: `$STANDALONE`)
- `tools/publish.ps1` (line 10: `$STANDALONE_GODOT`)

### Opening the project

This is a standard Godot 4 project. Just open the `project.godot` file at the repo root with your Godot editor (or drag the folder into Godot's project manager). No special setup required beyond having the binary above.

**Rendering:** The project uses `renderer = gl_compatibility` (pixel-art optimized). **Internal viewport is 480×270**, displayed at 4× to reach 1920×1080. Gameplay is constrained to a 216-pixel-wide **playfield band** down the middle; the side gutters host the HUD and glass panels. This matters — see Doc 02 and Doc 06 for coordinate-space gotchas.

---

## Running & verifying your changes

You have three ways to test. Use them in this order, because each one catches different kinds of failures.

### 1. Headless smoke test (fastest)

A quick "does the project load?" check:

```powershell
godot --path . --headless --quit-after 2
```

This boots the editor with no UI and exits after 2 seconds. If you see parse errors, it stops with a non-zero exit code. **But read the next section** — this is not enough.

### 2. Full parse check (scenes only)

```powershell
tools/parse_check.ps1
```

This script loads every user-facing scene (`main.tscn`, `main_menu.tscn`, `dev_menu.tscn`, `shipyard.tscn`, etc.) and checks for `SCRIPT ERROR`, `Parse Error`, or `Failed to load` messages. It's a gate we run before publishing to catch scene setup issues.

**Important limitation:** `parse_check` loads scenes but does NOT recompile scripts. It can **false-pass** — a scene loads fine in the editor's hot-reload environment, but a real boot shows compile errors. This is why we have rule 3 below.

See `tools/parse_check.ps1:10-38` for the exact scene list and error patterns it checks.

### 3. Headless boot of your changed scene (the real verify)

This is the **golden rule** for any script or scene you touched:

```powershell
godot --path . --headless res://scenes/main.tscn --quit-after 2 2>&1 | grep -i "script error\|parse error\|cannot infer\|failed to load"
```

Boot the actual scene headless and grep for error lines. This runs a real GDScript compile + load cycle, catching the kinds of errors `parse_check` misses (e.g., bad type annotations, missing autoloads, `:=` on non-inferrable types).

**Why?** The editor runs scripts in a permissive hot-reload environment where certain errors silently become Variants. A headless boot forces a true compile. (See CLAUDE.md and Doc 06 for the `:=` and `Variant` gotchas.)

---

## The dev menu & tuning workflow

### Finding the dev menu

Press the **Dev Menu** button on the main menu to reach `scenes/dev_menu.tscn`. It's a 3-column grid of 11 developer tools:

**Authoring tools** (edit definitions):
- [ Wave Editor ]
- [ Movement Patterns ]
- [ Shoot Patterns ]
- [ Weapons ]
- [ Shipyard ]

**Tuners / labs** (tweak & iterate live):
- [ Parallax Tuner ]
- [ Asteroid Lab ]
- [ Shader Lab ] (fire/compare shader effects — embers, shields, glow, full gallery)
- [ Smart Mount Lab ] (auto-turret tuner — live ship + randomized targets + traverse/dispersion/arc/range knobs, Copy GDScript; `scripts/dev/smart_mount_lab.gd`)

**Test launchers** (play-test specific scenarios):
- [ Combat Lab ] (HD screen: configure a ship — primary/secondary/modules + marks — then launch a chosen encounter: combat w/ faction+depth, hazard, boss, beam showcase, or custom level; `scripts/dev/combat_lab.gd`)
- [ Hangar ]
- [ EM Torpedo Test ] · [ All-Signal Sector ] (direct one-off launches)

> The exact button set drifts — `scripts/dev_menu.gd` is the source of truth.

### The "human-iterated, agent-consumed" workflow

**Context is the scarce resource.** The project follows a principle: **iteration-heavy, numeric/visual tuning belongs in a TUNER a human runs, not in edit-run-look loops by an agent.**

If you're adding a feature that has 3+ numeric knobs (color, size, speed, timing, etc.):

1. **Check if a tuner exists.** Look in `scripts/dev/` for a tool that fits (e.g., `parallax_tuner.gd`, `ui_designer.gd`, `asteroid_lab.gd`). If yes, ask the human to run it, tune the values, and copy-paste the exported GDScript snippet into your code. That snippet persists to `user://tuners/<name>.json`.

2. **No tuner for your system?** Build one. Use `scripts/dev/ui_designer.gd` as a reference — it's a model implementation with a **Copy GDScript** button that emits a paste-ready snippet. Your tuner must have this button; without it, the handoff to the human is broken.

3. **For visual mechanics** (explosions, trails, shader effects, parallax behavior), write a one-shot capture script + PowerShell wrapper:
   - `tools/capture_<mechanic>.gd` — loads the mechanic in isolation, renders frames
   - `tools/capture_<mechanic>.ps1` — runs the GDScript, pipes frames to ffmpeg, outputs a GIF to `captures/`
   - Post the GIF to Discord so the designer can eyeball it; **don't read PNG frames yourself** unless you're debugging a specific bug.

See CLAUDE.md "Workflow: human-iterated, agent-consumed" for the full rules — this doc just orients you.

---

## The contribution loop (how to push changes)

Here's the cycle for making a change:

### 1. Branch

```bash
git checkout -b feature/my-feature
```

Work on your feature as usual.

### 2. Verify (the three-level check)

Before committing, run all three verification steps:

1. **Headless smoke:** `godot --path . --headless --quit-after 2`
2. **Parse check:** `tools/parse_check.ps1`
3. **Headless boot of your changed scene:** Boot the scene you touched and grep for errors (see "Headless boot of your changed scene" above)

If anything fails, fix it before moving on.

### 3. Commit

```bash
git add scripts/my_script.gd scenes/my_scene.tscn
git commit -m "brief message explaining the why"
```

**Crucial:** When Godot creates or modifies a scene (`.tscn`), it generates a **`.uid` sidecar file**. These are Godot internal identifiers. **Commit them — never edit them by hand or ignore them.** Without `.uid` files in version control, other contributors' scenes break when they load.

```bash
git add scenes/my_scene.tscn.uid
git commit -m "…"
```

See Doc 06 "Conventions & Gotchas" for more on `.uid` files and other traps.

### 4. Push

```bash
git push -u origin feature/my-feature
```

**Working-branch pushes are fine without asking.** This keeps the team in sync.

Then open a pull request (or ask the maintainer to review your branch).

### 5. Publishing (the hard gate)

**Never run `tools/publish.ps1` or `butler push` without explicit approval from the maintainer.**

When the maintainer *does* approve a publish, they'll run:

```powershell
tools/publish.ps1 -Version "0.1.NN"
```

This script:
1. Runs `parse_check.ps1` (gates on all scenes parsing clean)
2. Bumps `config/version` in `project.godot`
3. Exports the Web preset to `../Starblasters_html/` (one level up)
4. Validates the `.pck` file mtime advanced (detects silent no-ops)
5. Runs `butler push` to the itch.io channel `cswendrowski/starblaster:html`

See `tools/publish.ps1:1-60` for the implementation.

---

## Key conventions at a glance

Read these in full in Doc 06, but here are the five that bite hardest:

1. **Gameplay bounds come from `Playfield`, never the viewport.** Import `scripts/playfield.gd` and use `Playfield.X_MIN`, `X_MAX`, `CENTER`, `clamp_pos`. (Doc 02.)
2. **Projectiles parent to `get_tree().root`, never to the shooter.** The shooter `queue_free`s and takes its bullets with it. (Doc 05.)
3. **`parse_check` is not enough — boot the scene headless to verify.** Parse_check false-passes compile errors. (This doc, rule 3 above.)
4. **Commit `.uid` sidecar files; never hand-edit them.** (Doc 06.)
5. **Never `butler` or publish without explicit OK from the maintainer.** (This doc, section 5 above.)

---

## Next steps

- **Before you touch code:** Read Doc 02 "Architecture" to understand the scene flow, autoloads, and coordinate space.
- **Before you commit:** Keep Doc 06 "Conventions & Gotchas" open as a checklist.
- **Adding a specific system?** Jump to Doc 03 (enemies), Doc 04 (parts/economy), or Doc 05 (projectiles/effects).
