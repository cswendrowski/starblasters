extends RefCounted

# Shared constants for the dock cinematics (outpost_arrival + patrol_start), factored out of their
# duplicated copies (Roman 2026-07-02 refactor). Only the values that were IDENTICAL in both screens
# live here. The intentionally-divergent ones stay per-screen: outpost uses a 64px engine-light texture
# at ENGINE_LIGHT_SCALE 0.45, patrol a 128px one at 0.3.

const PF = preload("res://scripts/systems/playfield.gd")

# Engine glow + light look (identical across both screens).
const ENGINE_GLOW_COLOR := Color(0.0, 0.827, 1.0)   # #00d3ff — in-game engine glowmask
const ENGINE_LIGHT_COLOR := Color(0.10, 0.60, 1.0)
const ENGINE_LIGHT_ENERGY := 1.8          # bright — the engines are the dock's main light in the dark bay
const ENGINE_FLARE_PEAK := 2.2            # energy × at the moment of launch (accelerating out of the bay)
const ENGINE_FLARE_SCALE := 1.7           # light-size × at launch (the bright spot blooms as it leaves)

# Fly-off target (off the top edge, same as _run_outro).
const FLYOFF_TARGET_Y := -120.0

# Native viewport + HD compositing geometry.
const NATIVE_W := 480.0
const NATIVE_H := 270.0
const SHIP_X := NATIVE_W / 2.0      # 240 — native viewport centre
const HD_SCALE := 4.0
const HD_W := 1920.0
const HD_H := 1080.0
const GUTTER_HD := PF.X_MIN * HD_SCALE   # 528 — left panel / mask right edge
const RIGHT_HD := PF.X_MAX * HD_SCALE     # 1392 — right panel / mask left edge
