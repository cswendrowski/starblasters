---
name: capture
description: Produce a GIF of a visual mechanic and post it to Discord in one go. Use whenever you need to show the maintainer a visual change (a new effect, an enemy's motion, a HUD tweak). Scaffolds a one-shot capture script if none exists, runs it through ffmpeg, self-reviews the GIF, and posts with a designer-level caption. Chains the capture-scripter / capture-poster agents.
---

# /capture — show a visual in one command

The project's visual workflow is capture → GIF → Discord. **Don't read raw PNG
frames to evaluate a visual** unless actively debugging a specific pixel bug —
make the GIF and look at that. (Memory `feedback_visual_workflow`.)

## Procedure

### 1. Find or scaffold the capture script
- Look for an existing `tools/capture_<mechanic>.gd` + `tools/capture_<mechanic>.ps1`.
- If none exists, use the **capture-scripter** agent to scaffold one: it boots a
  minimal scene, exercises the mechanic, dumps PNG frames, and pipes them to
  ffmpeg → GIF in `captures/`.

### 2. Run it
Run the `.ps1` (it invokes Godot headless to dump frames, then ffmpeg). Output
lands in `captures/<name>.gif`.

### 3. Zoom if the subject is small
Capture frames render at **full window resolution** (~5× the 480-wide viewport),
so a 16px sprite is tiny in the full frame. If the subject is small, re-encode
with a proportional crop + nearest-neighbor upscale around the action:
```
ffmpeg -y -framerate 30 -i frames_%04d.png \
  -vf "crop=in_w*0.42:in_h*0.62:in_w*0.16:in_h*0.28,scale=-1:600:flags=neighbor,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" out.gif
```
Tune the crop fractions to frame the subject (it moves — frame its whole path).

### 4. Self-review the GIF (required)
Read the produced GIF once to confirm it actually shows the thing and isn't
black/empty/broken (capture warm-up frames are often black — check a mid-action
frame if the first looks empty). If it's wrong, fix and re-capture — don't post
a broken GIF.

### 5. Post to Discord
Use the **capture-poster** agent, or post directly via the reply tool with the
GIF attached. Caption at a designer level: what the change is, and name any
visual uncertainty ("glow intensity is a first pass — easy to crank up").

## Notes
- You own the Discord channel — if you use capture-poster, that agent is the one
  exception that's allowed to post; any OTHER subagent must never post.
- Cross-refs: memory `feedback_visual_workflow`, agents capture-scripter / capture-poster.
